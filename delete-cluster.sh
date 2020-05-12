#!/bin/bash

set -e

CLUSTER_NAME=$1
REGION=$2

if [ -z $CLUSTER_NAME ] || [ -z $REGION ]
then
  echo "\nPlease enter cluster name [ ./delete-cluster.sh <CLUSTER_NAME> <AWS_REGION>]"
  exit 1
fi


NODEGROUP_NAME=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION -o json | jq -r '.[]|.Name')

NODEGROUP_SG=$(aws ec2 describe-security-groups --region $REGION --filters Name=tag:alpha.eksctl.io/nodegroup-name,Values=$NODEGROUP_NAME | jq -r '.SecurityGroups|.[]|.GroupId')
CONTROL_SG=$(aws ec2 describe-security-groups --region $REGION --filters Name=tag:Name,Values=eksctl-$CLUSTER_NAME-cluster/ControlPlaneSecurityGroup | jq -r '.SecurityGroups|.[]|.GroupId')


echo "De-Referencing Security Groups [ $NODEGROUP_SG ] and [ $CONTROL_SG ] vice versa"
at=$(aws ec2 revoke-security-group-ingress --group-id $NODEGROUP_SG --source-group $CONTROL_SG --protocol tcp --port 2049 --region $REGION)
at=$(aws ec2 revoke-security-group-ingress --group-id $CONTROL_SG --source-group $NODEGROUP_SG --protocol tcp --port 2049 --region $REGION)


ROLE_ARN=$(eksctl get iamidentitymapping --cluster ${CLUSTER_NAME} --region $REGION --output json | jq -r '.[0].rolearn')
ROLE_NAME=$(aws iam list-roles | jq  -r --arg ROLE_ARN "$ROLE_ARN" '.[] | .[] | select(.Arn==$ROLE_ARN) | .RoleName')
echo "Detaching arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess to the RoleName: ${ROLE_NAME}"
at=$(aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn arn:aws:iam::aws:policy/AmazonElasticFileSystemReadOnlyAccess)


EFS_ID=$(aws efs describe-file-systems --creation-token $CLUSTER_NAME --region $REGION | jq -r '.FileSystems | .[] | .FileSystemId')
MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id $EFS_ID --region $REGION | jq -r '.MountTargets | .[] | .MountTargetId')
for mt in $MOUNT_TARGETS
do
  echo "delete mount target [$mt]"
  at=$(aws efs delete-mount-target --mount-target-id $mt --region $REGION)
done

echo "waiting to finish mount target deletion"
sleep 60

echo "Deleting EFS $EFS_ID"
at=$(aws efs delete-file-system --file-system-id $EFS_ID --region $REGION)

echo "Deleting cluster [ $CLUSTER_NAME ]"
eksctl delete cluster --name $CLUSTER_NAME --region $REGION
