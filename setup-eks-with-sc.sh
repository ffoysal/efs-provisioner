#!/bin/bash


CLUSTER_NAME=$1
REGION=$2

if [ -z $CLUSTER_NAME ] || [ -z $REGION ]
then
  echo "\nPlease enter cluster name [ ./setup-eks-with-sc.sh <CLUSTER_NAME> <AWS_REGION>]"
  exit 1
fi

echo "Create cluster. It will take ~10 minutes"
eksctl create cluster --name ${CLUSTER_NAME} --nodes-min=5  --node-volume-size=50 --nodes-max=7 --region=${REGION} --zones=${REGION}a,${REGION}b,${REGION}c

CURRENT_CLUSTER=$(kubectl config current-context)


if [[ ! $CURRENT_CLUSTER =~ $CLUSTER_NAME ]]
then
  echo "Current Cluster in ~/.kube/config not found"
  exit 1
fi

ROLE_ARN=$(eksctl get iamidentitymapping --cluster ${CLUSTER_NAME} --output yaml --region $REGION | jq -r '.[0].rolearn')
ROLE_NAME=$(ws iam list-roles | jq  -r --arg ROLE_ARN "$ROLE_ARN" '.[] | .[] | select(.Arn==$ROLE_ARN) | .RoleName')
echo "Role ARN: ${ROLE_NAME}"
if [ -z $ROLE_NAME ]
then
  echo "Role Not found to create EFS"
  exit 1
fi

echo "Attaching arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess to the RoleName: ${ROLE_NAME}"
aws iam attach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess

echo "Create EFS file storage"
EFS_ID=$(aws efs create-file-system --creation-token $CLUSTER_NAME --tags Key=Name,Value=$CLUSTER_NAME --region $REGION | jq -r '. | .FileSystemId')


SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME  --region $REGION | jq -r '.cluster.resourcesVpcConfig.subnetIds | .[]')
SECURITY_GROUP_ID=$(aws eks describe-cluster --name $CLUSTER_NAME  --region $REGION | jq -r '.cluster.resourcesVpcConfig.securityGroupIds | .[]')

echo "Waiting to finish storage creation"
sleep 60

for subnet in $SUBNET_IDS
do
  echo "Creating mount point for subent: $subnet"
  aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $subnet --security-group $SECURITY_GROUP_ID --region $REGION
done

NODEGROUP_NAME=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION -o json | jq -r '.[]|.Name')

NODEGROUP_SG=$(aws ec2 describe-security-groups --region $REGION --filters Name=tag:alpha.eksctl.io/nodegroup-name,Values=$NODEGROUP_NAME | jq -r '.SecurityGroups|.[]|.GroupId')
CONTROL_SG=$(aws ec2 describe-security-groups --region $REGION --filters Name=tag:Name,Values=eksctl-$CLUSTER_NAME-cluster/ControlPlaneSecurityGroup | jq -r '.SecurityGroups|.[]|.GroupId')

echo "Add NFS Ingress to both $NODEGROUP_SG and $CONTROL_SG vice versa"
aws ec2 authorize-security-group-ingress --group-id $NODEGROUP_SG --protocol tcp --port 2049 --source-group $CONTROL_SG --region $REGION
aws ec2 authorize-security-group-ingress --group-id $CONTROL_SG --protocol tcp --port 2049 --source-group $NODEGROUP_SG --region $REGION


echo "Waiting to finish mounting"
sleep 60

yq w -i resources/kustomization.yaml 'configMapGenerator[0].literals[0]' fileSystemId=$EFS_ID
yq w -i resources/kustomization.yaml 'configMapGenerator[0].literals[1]' efsRegion=$REGION

kustomize build resources | kubectl apply -f -
echo "Waiting to stable efs provisioner...."
sleep 90