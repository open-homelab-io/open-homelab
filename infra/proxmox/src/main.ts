import { readFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { App, S3Backend, TerraformOutput, TerraformStack } from "cdktn";
import { Construct } from "constructs";
import { parse } from "yaml";
import { ProxmoxProvider } from "../.gen/providers/proxmox/provider/index.js";
import { VirtualEnvironmentDownloadFile } from "../.gen/providers/proxmox/virtual-environment-download-file/index.js";
import { VirtualEnvironmentVm, VirtualEnvironmentVmDisk } from "../.gen/providers/proxmox/virtual-environment-vm/index.js";

type NodeRole = "controlplane" | "worker";
const tofuNull = null as unknown as undefined;

interface LabNode {
  name: string;
  role: NodeRole;
  nodeName?: string;
  vmId: number;
  address: string;
  macAddress?: string;
  cores?: number;
  memoryMb?: number;
  diskSizeGb?: number;
}

interface LabConfig {
  cluster: {
    name: string;
    dnsDomain: string;
    gateway: string;
    cidrSuffix: number;
  };
  proxmox: {
    insecure: boolean;
    defaultNodeName: string;
    datastoreId: string;
    isoDatastoreId: string;
    isoNodeName?: string;
    networkBridge: string;
    vlanId?: number;
    talosImageUrl: string;
    talosImageFileName: string;
    talosImageFileId: string;
    longhornDataDisk?: {
      enabled?: boolean;
      interface?: string;
      sizeGb?: number;
      datastoreByNodeName: Record<string, string>;
    };
    ssh?: {
      agent?: boolean;
      username?: string;
      nodeAddressSource?: "api" | "dns";
      nodes?: Array<{
        name: string;
        address: string;
        port?: number;
      }>;
    };
  };
  defaults: {
    cpuType: string;
    diskInterface: string;
    diskSizeGb: number;
    memoryMb: number;
    cores: number;
  };
  nodes: LabNode[];
}

class ProxmoxStack extends TerraformStack {
  public constructor(scope: Construct, id: string, config: LabConfig) {
    super(scope, id);

    const stateBucket = process.env.TF_STATE_BUCKET;
    if (stateBucket) {
      new S3Backend(this, {
        bucket: stateBucket,
        key: process.env.TF_STATE_KEY ?? "open-homelab/proxmox/production.tfstate",
        region: process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION ?? "us-east-1",
        encrypt: true,
        useLockfile: true,
      });
    }

    new ProxmoxProvider(this, "proxmox", {
      insecure: config.proxmox.insecure,
      ssh: config.proxmox.ssh
        ? {
            agent: config.proxmox.ssh.agent,
            username: config.proxmox.ssh.username,
            nodeAddressSource: config.proxmox.ssh.nodeAddressSource,
            nodeAttribute: config.proxmox.ssh.nodes,
          }
        : undefined,
    });

    const talosImage = new VirtualEnvironmentDownloadFile(this, "talos-metal-amd64-iso", {
      contentType: "iso",
      datastoreId: config.proxmox.isoDatastoreId,
      fileName: config.proxmox.talosImageFileName,
      nodeName: config.proxmox.isoNodeName ?? config.proxmox.defaultNodeName,
      overwrite: true,
      overwriteUnmanaged: true,
      url: config.proxmox.talosImageUrl,
    });

    for (const node of config.nodes) {
      const cores = node.cores ?? config.defaults.cores;
      const memoryMb = node.memoryMb ?? config.defaults.memoryMb;
      const diskSizeGb = node.diskSizeGb ?? config.defaults.diskSizeGb;
      const nodeName = node.nodeName ?? config.proxmox.defaultNodeName;
      const disks: VirtualEnvironmentVmDisk[] = [
        {
          datastoreId: config.proxmox.datastoreId,
          interface: config.defaults.diskInterface,
          size: diskSizeGb,
        },
      ];

      if (node.role === "worker" && config.proxmox.longhornDataDisk?.enabled !== false) {
        const dataDiskDatastoreId = config.proxmox.longhornDataDisk?.datastoreByNodeName[nodeName];

        if (!dataDiskDatastoreId) {
          throw new Error(`Missing proxmox.longhornDataDisk.datastoreByNodeName entry for ${node.name} on ${nodeName}`);
        }

        disks.push({
          datastoreId: dataDiskDatastoreId,
          interface: config.proxmox.longhornDataDisk?.interface ?? "scsi1",
          size: config.proxmox.longhornDataDisk?.sizeGb ?? 200,
          backup: false,
          cache: "none",
          discard: "on",
          iothread: true,
          replicate: false,
        });
      }

      new VirtualEnvironmentVm(this, node.name, {
        name: node.name,
        description: `${config.cluster.name} ${node.role} node`,
        nodeName,
        vmId: node.vmId,
        tags: [config.cluster.name, node.role, "talos", "cdktn"],
        started: true,
        onBoot: true,
        cpu: {
          cores,
          type: config.defaults.cpuType,
        },
        memory: {
          dedicated: memoryMb,
        },
        disk: disks,
        cdrom: {
          fileId: talosImage.id,
        },
        networkDevice: [
          {
            bridge: config.proxmox.networkBridge,
            disconnected: false,
            enabled: tofuNull,
            firewall: false,
            macAddress: node.macAddress ?? tofuNull,
            model: "virtio",
            mtu: tofuNull,
            queues: tofuNull,
            rateLimit: tofuNull,
            trunks: tofuNull,
            vlanId: config.proxmox.vlanId ?? tofuNull,
          },
        ],
        initialization: {
          datastoreId: config.proxmox.datastoreId,
          ipConfig: [
            {
              ipv4: {
                address: `${node.address}/${config.cluster.cidrSuffix}`,
                gateway: config.cluster.gateway,
              },
            },
          ],
        },
        operatingSystem: {
          type: "l26",
        },
      });
    }

    new TerraformOutput(this, "node_addresses", {
      value: Object.fromEntries(config.nodes.map((node) => [node.name, node.address])),
    });
    new TerraformOutput(this, "longhorn_data_disks", {
      value: Object.fromEntries(
        config.nodes
          .filter((node) => node.role === "worker")
          .map((node) => {
            const nodeName = node.nodeName ?? config.proxmox.defaultNodeName;
            return [
              node.name,
              {
                interface: config.proxmox.longhornDataDisk?.interface ?? "scsi1",
                datastoreId: config.proxmox.longhornDataDisk?.datastoreByNodeName[nodeName],
                sizeGb: config.proxmox.longhornDataDisk?.sizeGb ?? 200,
              },
            ];
          }),
      ),
    });
  }
}

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const configPath = resolveFromRepoRoot(process.env.LAB_CONFIG ?? "infra/proxmox/config/production.yaml");
const config = parse(readFileSync(configPath, "utf8")) as LabConfig;

const app = new App();
new ProxmoxStack(app, "production", config);
app.synth();

function resolveFromRepoRoot(path: string): string {
  return isAbsolute(path) ? path : resolve(repoRoot, path);
}
