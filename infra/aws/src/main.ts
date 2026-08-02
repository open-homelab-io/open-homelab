import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { App, CfnOutput, Duration, RemovalPolicy, Stack, StackProps, Tags } from "aws-cdk-lib";
import { CfnRole, CfnPolicy } from "aws-cdk-lib/aws-iam";
import { CfnProfile, CfnTrustAnchor } from "aws-cdk-lib/aws-rolesanywhere";
import { BlockPublicAccess, Bucket, BucketEncryption, ObjectOwnership } from "aws-cdk-lib/aws-s3";
import { Construct } from "constructs";

class OpenTofuStateStack extends Stack {
  public constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, props);

    const region = Stack.of(this).region;
    const account = Stack.of(this).account;
    const bucketName =
      process.env.TF_STATE_BUCKET ?? `open-homelab-opentofu-state-${account}-${region}`;
    const stateKey = process.env.TF_STATE_KEY ?? "open-homelab/proxmox/production.tfstate";

    const bucket = new Bucket(this, "OpenTofuStateBucket", {
      bucketName,
      versioned: true,
      encryption: BucketEncryption.S3_MANAGED,
      blockPublicAccess: BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      objectOwnership: ObjectOwnership.BUCKET_OWNER_ENFORCED,
      removalPolicy: RemovalPolicy.RETAIN,
      autoDeleteObjects: false,
      lifecycleRules: [
        {
          id: "abort-incomplete-multipart-uploads",
          abortIncompleteMultipartUploadAfter: Duration.days(7),
        },
      ],
    });

    Tags.of(bucket).add("Project", "open-homelab");
    Tags.of(bucket).add("Purpose", "opentofu-state");

    new CfnOutput(this, "OpenTofuStateBucketName", {
      value: bucket.bucketName,
    });
    new CfnOutput(this, "OpenTofuStateRegion", {
      value: region,
    });
    new CfnOutput(this, "ProxmoxOpenTofuStateKey", {
      value: stateKey,
    });
  }
}

class DnsAutomationStack extends Stack {
  public constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, props);

    const region = Stack.of(this).region;
    const partition = Stack.of(this).partition;
    const hostedZoneId = requiredEnv("PUBLIC_HOSTED_ZONE_ID");
    const publicDomain = requiredEnv("PUBLIC_DOMAIN");
    const clientCommonName = process.env.IAM_ROLES_ANYWHERE_CLIENT_CN ?? "open-homelab-dns-automation";
    const caCertPath = resolve(process.cwd(), process.env.IAM_ROLES_ANYWHERE_CA_CERT_PATH ?? "../../.context/iam-roles-anywhere/ca.crt");

    if (!existsSync(caCertPath)) {
      throw new Error(
        `IAM Roles Anywhere CA certificate not found at ${caCertPath}. Run scripts/bootstrap-rolesanywhere-ca.sh before synthesizing this stack.`,
      );
    }

    const caCert = readFileSync(caCertPath, "utf8").trim();
    const hostedZoneArn = `arn:${partition}:route53:::hostedzone/${hostedZoneId}`;

    const trustAnchor = new CfnTrustAnchor(this, "DnsAutomationTrustAnchor", {
      name: "open-homelab-dns-automation",
      enabled: true,
      source: {
        sourceType: "CERTIFICATE_BUNDLE",
        sourceData: {
          x509CertificateData: caCert,
        },
      },
      tags: stackTags("dns-automation"),
    });

    const role = new CfnRole(this, "DnsAutomationRole", {
      roleName: process.env.DNS_AUTOMATION_ROLE_NAME ?? "open-homelab-dns-automation",
      description: "Route53 automation role assumed by homelab Kubernetes workloads through IAM Roles Anywhere.",
      assumeRolePolicyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Principal: {
              Service: "rolesanywhere.amazonaws.com",
            },
            Action: ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"],
            Condition: {
              ArnEquals: {
                "aws:SourceArn": trustAnchor.attrTrustAnchorArn,
              },
              StringEquals: {
                "aws:PrincipalTag/x509Subject/CN": clientCommonName,
              },
            },
          },
        ],
      },
      tags: stackTags("dns-automation"),
    });

    new CfnPolicy(this, "DnsAutomationRoute53Policy", {
      policyName: "open-homelab-route53-dns-automation",
      roles: [role.ref],
      policyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Sid: "ListHostedZonesForDiscovery",
            Effect: "Allow",
            Action: ["route53:ListHostedZones", "route53:ListHostedZonesByName"],
            Resource: "*",
          },
          {
            Sid: "ReadAndChangeConfiguredHostedZone",
            Effect: "Allow",
            Action: ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"],
            Resource: hostedZoneArn,
          },
          {
            Sid: "WaitForRecordChanges",
            Effect: "Allow",
            Action: "route53:GetChange",
            Resource: `arn:${partition}:route53:::change/*`,
          },
        ],
      },
    });

    const profile = new CfnProfile(this, "DnsAutomationProfile", {
      name: "open-homelab-dns-automation",
      enabled: true,
      acceptRoleSessionName: true,
      durationSeconds: 3600,
      requireInstanceProperties: false,
      roleArns: [role.attrArn],
      tags: stackTags("dns-automation"),
    });

    Tags.of(this).add("Project", "open-homelab");
    Tags.of(this).add("PublicDomain", publicDomain);
    Tags.of(this).add("HostedZoneId", hostedZoneId);

    new CfnOutput(this, "DnsAutomationRoleArn", {
      value: role.attrArn,
    });
    new CfnOutput(this, "RolesAnywhereProfileArn", {
      value: profile.attrProfileArn,
    });
    new CfnOutput(this, "RolesAnywhereTrustAnchorArn", {
      value: trustAnchor.attrTrustAnchorArn,
    });
    new CfnOutput(this, "RolesAnywhereClientCommonName", {
      value: clientCommonName,
    });
    new CfnOutput(this, "DnsAutomationHostedZoneId", {
      value: hostedZoneId,
    });
  }
}

function stackTags(purpose: string) {
  return [
    { key: "Project", value: "open-homelab" },
    { key: "Purpose", value: purpose },
  ];
}

const app = new App();

const defaultEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT ?? process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION ?? process.env.AWS_REGION ?? process.env.AWS_DEFAULT_REGION ?? "us-east-1",
};

if (envFlag("AWS_OPENTOFU_STATE_ENABLED")) {
  new OpenTofuStateStack(app, "open-homelab-opentofu-state", {
    env: defaultEnv,
  });
}

if (envFlag("AWS_DNS_AUTOMATION_ENABLED")) {
  new DnsAutomationStack(app, process.env.IAM_ROLES_ANYWHERE_STACK_NAME ?? "open-homelab-dns-automation", {
    env: defaultEnv,
  });
}

function envFlag(name: string): boolean {
  const value = process.env[name]?.trim().toLowerCase();
  return value === "1" || value === "true" || value === "yes" || value === "on";
}

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required when AWS_DNS_AUTOMATION_ENABLED is enabled.`);
  }
  return value;
}
