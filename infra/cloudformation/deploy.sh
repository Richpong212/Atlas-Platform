#!/usr/bin/env bash
set -euo pipefail

ENV=${1:-dev}

echo "Uploading templates..."
aws s3 cp infra/cloudformation/network/network.yaml s3://codegenitor-cfn-templates/atlas/network.yaml
aws s3 cp infra/cloudformation/security/security.yaml s3://codegenitor-cfn-templates/atlas/security.yaml
aws s3 cp infra/cloudformation/ecr/ecr.yaml s3://codegenitor-cfn-templates/atlas/ecr.yaml
aws s3 cp infra/cloudformation/iam/eks-iam.yaml s3://codegenitor-cfn-templates/atlas/eks-iam.yaml
aws s3 cp infra/cloudformation/eks/eks.yaml s3://codegenitor-cfn-templates/atlas/eks.yaml

echo "Deploying stack..."
aws cloudformation deploy \
  --template-file infra/cloudformation/root/root.yaml \
  --stack-name atlas-${ENV}-root \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides file://infra/cloudformation/parameters/${ENV}.json

echo "Done."