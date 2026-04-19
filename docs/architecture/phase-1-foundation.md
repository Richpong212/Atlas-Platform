# Phase 1 Goal

Provision these with **CloudFormation**:

- VPC
- 2 public subnets
- 2 private subnets
- Internet Gateway
- NAT Gateway
- route tables
- security groups
- ECR repositories
- EKS cluster
- EKS managed node group

We’ll do it with **nested stacks**, because that keeps the repo clean and public-repo friendly.

# What you will learn in this phase

- how to break infra into reusable CloudFormation stacks
- how AWS networking supports EKS
- why public and private subnets both matter
- how EKS depends on IAM, networking, and security groups
- how to structure infrastructure for growth instead of chaos

# Folder Structure for Phase 1

Create this first:

```text
atlas-platform/
├── infra/
│   └── cloudformation/
│       ├── root/
│       │   └── root.yaml
│       ├── network/
│       │   └── network.yaml
│       ├── security/
│       │   └── security.yaml
│       ├── ecr/
│       │   └── ecr.yaml
│       ├── iam/
│       │   └── eks-iam.yaml
│       ├── eks/
│       │   └── eks.yaml
│       └── parameters/
│           └── dev.json
└── docs/
    └── architecture/
        └── phase-1-foundation.md
```

# Phase 1 Build Order

We build in this exact order:

## Step 1

Create the **network stack**

## Step 2

Create the **security stack**

## Step 3

Create the **ECR stack**

## Step 4

Create the **IAM stack** for EKS

## Step 5

Create the **EKS stack**

## Step 6

Create the **root stack** that ties them together

That order matters because:

- EKS needs networking
- EKS needs IAM roles
- node groups need subnets and security groups

---

# Design Decisions We Are Locking In

## Region

Use one AWS region consistently.

## AZ Strategy

Use **2 Availability Zones**.

## Subnet Design

- 2 public subnets
- 2 private subnets

## EKS Placement

- worker nodes in **private subnets**
- NAT Gateway allows outbound internet access

## Repo Naming

We’ll use the prefix `atlas-dev` for dev resources.

---

# Resource Naming Standard

Use this pattern:

- `atlas-dev-vpc`
- `atlas-dev-public-subnet-a`
- `atlas-dev-private-subnet-a`
- `atlas-dev-eks-cluster`
- `atlas-dev-api-ecr`

This becomes important later when the project grows.

---

# Step 1 — Network Stack

This is the foundation.
Without this, nothing else is stable.

## What this stack creates

- VPC
- Internet Gateway
- 2 public subnets
- 2 private subnets
- Elastic IP for NAT
- NAT Gateway
- public route table
- private route table
- route associations

## Why this matters

### VPC

Defines the network boundary for the platform.

### Public subnets

Used for internet-facing resources like:

- NAT Gateway
- later ALB / ingress

### Private subnets

Used for:

- EKS worker nodes
- internal services

### NAT Gateway

Lets private workloads reach the internet for things like:

- pulling images
- installing packages
- talking to AWS APIs

without exposing them directly to inbound internet traffic.

---

# `infra/cloudformation/network/network.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "Network stack for Atlas Platform"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

  VpcCidr:
    Type: String
    Default: 10.0.0.0/16

  PublicSubnetACidr:
    Type: String
    Default: 10.0.1.0/24

  PublicSubnetBCidr:
    Type: String
    Default: 10.0.2.0/24

  PrivateSubnetACidr:
    Type: String
    Default: 10.0.11.0/24

  PrivateSubnetBCidr:
    Type: String
    Default: 10.0.12.0/24

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsSupport: true
      EnableDnsHostnames: true
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-vpc

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-igw

  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  PublicSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs ""]
      CidrBlock: !Ref PublicSubnetACidr
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-public-subnet-a
        - Key: kubernetes.io/role/elb
          Value: "1"

  PublicSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs ""]
      CidrBlock: !Ref PublicSubnetBCidr
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-public-subnet-b
        - Key: kubernetes.io/role/elb
          Value: "1"

  PrivateSubnetA:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs ""]
      CidrBlock: !Ref PrivateSubnetACidr
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-private-subnet-a
        - Key: kubernetes.io/role/internal-elb
          Value: "1"

  PrivateSubnetB:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs ""]
      CidrBlock: !Ref PrivateSubnetBCidr
      MapPublicIpOnLaunch: false
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-private-subnet-b
        - Key: kubernetes.io/role/internal-elb
          Value: "1"

  NatEIP:
    Type: AWS::EC2::EIP
    DependsOn: VPCGatewayAttachment
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-nat-eip

  NatGateway:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatEIP.AllocationId
      SubnetId: !Ref PublicSubnetA
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-nat-gateway

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-public-rt

  PublicDefaultRoute:
    Type: AWS::EC2::Route
    DependsOn: VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnetARouteAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnetA
      RouteTableId: !Ref PublicRouteTable

  PublicSubnetBRouteAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnetB
      RouteTableId: !Ref PublicRouteTable

  PrivateRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-private-rt

  PrivateDefaultRoute:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway

  PrivateSubnetARouteAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnetA
      RouteTableId: !Ref PrivateRouteTable

  PrivateSubnetBRouteAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PrivateSubnetB
      RouteTableId: !Ref PrivateRouteTable

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref VPC
    Export:
      Name: !Sub atlas-${EnvironmentName}-VpcId

  PublicSubnetAId:
    Description: Public subnet A ID
    Value: !Ref PublicSubnetA
    Export:
      Name: !Sub atlas-${EnvironmentName}-PublicSubnetAId

  PublicSubnetBId:
    Description: Public subnet B ID
    Value: !Ref PublicSubnetB
    Export:
      Name: !Sub atlas-${EnvironmentName}-PublicSubnetBId

  PrivateSubnetAId:
    Description: Private subnet A ID
    Value: !Ref PrivateSubnetA
    Export:
      Name: !Sub atlas-${EnvironmentName}-PrivateSubnetAId

  PrivateSubnetBId:
    Description: Private subnet B ID
    Value: !Ref PrivateSubnetB
    Export:
      Name: !Sub atlas-${EnvironmentName}-PrivateSubnetBId
```

---

# Why the subnet tags matter

These tags are important for Kubernetes load balancer behavior later:

```yaml
kubernetes.io/role/elb: "1"
kubernetes.io/role/internal-elb: "1"
```

They help AWS and Kubernetes know which subnets are intended for:

- public load balancers
- internal load balancers

That is one of those details people often skip and then suffer later.

---

# Step 2 — Security Stack

Now create the security groups that EKS will use.

## `infra/cloudformation/security/security.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "Security stack for Atlas Platform"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

  VpcId:
    Type: AWS::EC2::VPC::Id

Resources:
  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for EKS control plane
      VpcId: !Ref VpcId
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-eks-cluster-sg

  NodeSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for EKS worker nodes
      VpcId: !Ref VpcId
      Tags:
        - Key: Name
          Value: !Sub atlas-${EnvironmentName}-eks-node-sg

  ClusterToNodeIngress443:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref NodeSecurityGroup
      IpProtocol: tcp
      FromPort: 443
      ToPort: 443
      SourceSecurityGroupId: !Ref ClusterSecurityGroup

  NodeToClusterIngress443:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref ClusterSecurityGroup
      IpProtocol: tcp
      FromPort: 443
      ToPort: 443
      SourceSecurityGroupId: !Ref NodeSecurityGroup

  NodeToNodeAllTraffic:
    Type: AWS::EC2::SecurityGroupIngress
    Properties:
      GroupId: !Ref NodeSecurityGroup
      IpProtocol: -1
      SourceSecurityGroupId: !Ref NodeSecurityGroup

  NodeEgressAll:
    Type: AWS::EC2::SecurityGroupEgress
    Properties:
      GroupId: !Ref NodeSecurityGroup
      IpProtocol: -1
      CidrIp: 0.0.0.0/0

  ClusterEgressAll:
    Type: AWS::EC2::SecurityGroupEgress
    Properties:
      GroupId: !Ref ClusterSecurityGroup
      IpProtocol: -1
      CidrIp: 0.0.0.0/0

Outputs:
  ClusterSecurityGroupId:
    Value: !Ref ClusterSecurityGroup
    Export:
      Name: !Sub atlas-${EnvironmentName}-ClusterSecurityGroupId

  NodeSecurityGroupId:
    Value: !Ref NodeSecurityGroup
    Export:
      Name: !Sub atlas-${EnvironmentName}-NodeSecurityGroupId
```

---

# Step 3 — ECR Stack

Each service gets its own repository.

## `infra/cloudformation/ecr/ecr.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "ECR repositories for Atlas Platform"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

Resources:
  ApiRepository:
    Type: AWS::ECR::Repository
    Properties:
      RepositoryName: !Sub atlas-${EnvironmentName}-api
      ImageScanningConfiguration:
        ScanOnPush: true
      ImageTagMutability: IMMUTABLE

  AuthRepository:
    Type: AWS::ECR::Repository
    Properties:
      RepositoryName: !Sub atlas-${EnvironmentName}-auth-service
      ImageScanningConfiguration:
        ScanOnPush: true
      ImageTagMutability: IMMUTABLE

  FrontendRepository:
    Type: AWS::ECR::Repository
    Properties:
      RepositoryName: !Sub atlas-${EnvironmentName}-frontend
      ImageScanningConfiguration:
        ScanOnPush: true
      ImageTagMutability: IMMUTABLE

Outputs:
  ApiRepositoryUri:
    Value: !GetAtt ApiRepository.RepositoryUri
    Export:
      Name: !Sub atlas-${EnvironmentName}-ApiRepositoryUri

  AuthRepositoryUri:
    Value: !GetAtt AuthRepository.RepositoryUri
    Export:
      Name: !Sub atlas-${EnvironmentName}-AuthRepositoryUri

  FrontendRepositoryUri:
    Value: !GetAtt FrontendRepository.RepositoryUri
    Export:
      Name: !Sub atlas-${EnvironmentName}-FrontendRepositoryUri
```

---

# Why `IMMUTABLE` matters

This is a very strong default.

It prevents you from doing dumb things like reusing the same tag and silently changing what it points to.

That supports the rule:

**same tag = same image**

---

# Step 4 — IAM for EKS

## `infra/cloudformation/iam/eks-iam.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "IAM roles for Atlas EKS"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

Resources:
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub atlas-${EnvironmentName}-eks-cluster-role
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

  EKSNodeRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub atlas-${EnvironmentName}-eks-node-role
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

Outputs:
  EKSClusterRoleArn:
    Value: !GetAtt EKSClusterRole.Arn
    Export:
      Name: !Sub atlas-${EnvironmentName}-EKSClusterRoleArn

  EKSNodeRoleArn:
    Value: !GetAtt EKSNodeRole.Arn
    Export:
      Name: !Sub atlas-${EnvironmentName}-EKSNodeRoleArn
```

---

# Step 5 — EKS Stack

## `infra/cloudformation/eks/eks.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "EKS stack for Atlas Platform"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

  ClusterName:
    Type: String
    Default: atlas-dev-eks-cluster

  EKSClusterRoleArn:
    Type: String

  EKSNodeRoleArn:
    Type: String

  PrivateSubnetAId:
    Type: AWS::EC2::Subnet::Id

  PrivateSubnetBId:
    Type: AWS::EC2::Subnet::Id

  ClusterSecurityGroupId:
    Type: AWS::EC2::SecurityGroup::Id

  NodeSecurityGroupId:
    Type: AWS::EC2::SecurityGroup::Id

Resources:
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: "1.31"
      RoleArn: !Ref EKSClusterRoleArn
      ResourcesVpcConfig:
        EndpointPrivateAccess: true
        EndpointPublicAccess: true
        SecurityGroupIds:
          - !Ref ClusterSecurityGroupId
        SubnetIds:
          - !Ref PrivateSubnetAId
          - !Ref PrivateSubnetBId

  EKSNodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodeRole: !Ref EKSNodeRoleArn
      Subnets:
        - !Ref PrivateSubnetAId
        - !Ref PrivateSubnetBId
      ScalingConfig:
        MinSize: 2
        DesiredSize: 2
        MaxSize: 3
      AmiType: AL2023_x86_64_STANDARD
      CapacityType: ON_DEMAND
      DiskSize: 20
      InstanceTypes:
        - t3.medium
      Labels:
        workload: general

Outputs:
  ClusterName:
    Value: !Ref EKSCluster
    Export:
      Name: !Sub atlas-${EnvironmentName}-ClusterName
```

---

# Note on the node security group parameter

The managed node group largely manages its own behavior, so `NodeSecurityGroupId` is not directly attached in this basic version of the template. That is okay for now. We keep the parameter because later, when we tighten the design, we may extend this with launch templates or additional node controls.

---

# Step 6 — Root Stack

This is the orchestrator.

## `infra/cloudformation/root/root.yaml`

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Description: "Root stack for Atlas Platform"

Parameters:
  EnvironmentName:
    Type: String
    Default: dev

Resources:
  NetworkStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://YOUR-BUCKET.s3.amazonaws.com/atlas/network.yaml
      Parameters:
        EnvironmentName: !Ref EnvironmentName

  SecurityStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://YOUR-BUCKET.s3.amazonaws.com/atlas/security.yaml
      Parameters:
        EnvironmentName: !Ref EnvironmentName
        VpcId: !GetAtt NetworkStack.Outputs.VpcId

  ECRStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://YOUR-BUCKET.s3.amazonaws.com/atlas/ecr.yaml
      Parameters:
        EnvironmentName: !Ref EnvironmentName

  IAMStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: https://YOUR-BUCKET.s3.amazonaws.com/atlas/eks-iam.yaml
      Parameters:
        EnvironmentName: !Ref EnvironmentName

  EKSStack:
    Type: AWS::CloudFormation::Stack
    DependsOn:
      - NetworkStack
      - SecurityStack
      - IAMStack
    Properties:
      TemplateURL: https://YOUR-BUCKET.s3.amazonaws.com/atlas/eks.yaml
      Parameters:
        EnvironmentName: !Ref EnvironmentName
        ClusterName: !Sub atlas-${EnvironmentName}-eks-cluster
        EKSClusterRoleArn: !GetAtt IAMStack.Outputs.EKSClusterRoleArn
        EKSNodeRoleArn: !GetAtt IAMStack.Outputs.EKSNodeRoleArn
        PrivateSubnetAId: !GetAtt NetworkStack.Outputs.PrivateSubnetAId
        PrivateSubnetBId: !GetAtt NetworkStack.Outputs.PrivateSubnetBId
        ClusterSecurityGroupId: !GetAtt SecurityStack.Outputs.ClusterSecurityGroupId
        NodeSecurityGroupId: !GetAtt SecurityStack.Outputs.NodeSecurityGroupId
```

Replace `YOUR-BUCKET` with your S3 bucket name later.

---

# Deployment Flow for Phase 1

## 1. Validate templates

```bash
aws cloudformation validate-template --template-body file://infra/cloudformation/network/network.yaml
aws cloudformation validate-template --template-body file://infra/cloudformation/security/security.yaml
aws cloudformation validate-template --template-body file://infra/cloudformation/ecr/ecr.yaml
aws cloudformation validate-template --template-body file://infra/cloudformation/iam/eks-iam.yaml
aws cloudformation validate-template --template-body file://infra/cloudformation/eks/eks.yaml
```

## 2. Upload nested templates to S3

```bash
aws s3 cp infra/cloudformation/network/network.yaml s3://codegenitor-cfn-templates/atlas/network.yaml
aws s3 cp infra/cloudformation/security/security.yaml s3://codegenitor-cfn-templates/atlas/security.yaml
aws s3 cp infra/cloudformation/ecr/ecr.yaml s3://codegenitor-cfn-templates/atlas/ecr.yaml
aws s3 cp infra/cloudformation/iam/eks-iam.yaml s3://codegenitor-cfn-templates/atlas/eks-iam.yaml
aws s3 cp infra/cloudformation/eks/eks.yaml s3://codegenitor-cfn-templates/atlas/eks.yaml
```

## 3. Deploy root stack

```bash
aws cloudformation deploy \
  --template-file infra/cloudformation/root/root.yaml \
  --stack-name atlas-dev-root \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides EnvironmentName=dev
```

---

# What to verify after deployment

## CloudFormation

Make sure all nested stacks finish successfully.

## VPC

Check:

- 1 VPC
- 2 public subnets
- 2 private subnets
- 1 NAT Gateway

## ECR

Check:

- atlas-dev-api
- atlas-dev-auth-service
- atlas-dev-frontend

## EKS

Check cluster exists:

```bash
aws eks list-clusters
```

Update kubeconfig:

```bash
aws eks update-kubeconfig --region YOUR_REGION --name atlas-dev-eks-cluster
```

Verify nodes:

```bash
kubectl get nodes
```

---

# What you should understand before moving on

Phase 1 is not “just infra.”

It establishes:

- the network boundary
- how Kubernetes will run privately
- where images will live
- how the cluster gets permission to function
- how nested stacks keep the design maintainable

That is why we started here.

# The exact next move

After these files are in place, **Phase 2** is:

- connect to EKS
- create namespaces
- install essential cluster tooling
- prepare for Argo CD and workloads

### RUNNING the Phase 1

####Load files in s3
aws s3 cp infra/cloudformation/network/network.yaml s3://codegenitor-cfn-templates/atlas/network.yaml
aws s3 cp infra/cloudformation/security/security.yaml s3://codegenitor-cfn-templates/atlas/security.yaml
aws s3 cp infra/cloudformation/ecr/ecr.yaml s3://codegenitor-cfn-templates/atlas/ecr.yaml
aws s3 cp infra/cloudformation/iam/eks-iam.yaml s3://codegenitor-cfn-templates/atlas/eks-iam.yaml
aws s3 cp infra/cloudformation/eks/eks.yaml s3://codegenitor-cfn-templates/atlas/eks.yaml

#### Veriy files in s3

aws s3 ls s3://codegenitor-cfn-templates/atlas/

#### Create the root stack

aws cloudformation create-stack \
 --stack-name atlas-dev-root \
 --template-body file://infra/cloudformation/root/root.yaml \
 --capabilities CAPABILITY_NAMED_IAM \
 --parameters file://infra/cloudformation/parameters/dev.json

#### Verify infrastructure

aws eks list-clusters

#### Connect kubectl

aws eks update-kubeconfig \
 --region us-east-1 \
 --name atlas-dev-eks-cluster

#### Verify nodes

kubectl get nodes

#### Verify ECR repos

aws ecr describe-repositories \
 --query "repositories[?contains(repositoryName, 'atlas-dev')].[repositoryName,repositoryUri]" \
 --output table

#### Destroy phase 1

aws cloudformation delete-stack --stack-name atlas-dev-root
aws cloudformation wait stack-delete-complete --stack-name atlas-dev-root
