# AWS EFS provisioner

This will help to creat

- eks cluster using [eksctl](eksctl.io)
- deploy aws-efs provisioner using [kustomize](kustomize.io)
- create a storage class name aws-efs into the cluster

## Prerequisites:

install following components before you start

- [eksctl](eksctl.io)
- [kustomize](kustomize.io)
- [jq](https://stedolan.github.io/jq/)
- [yq](https://mikefarah.gitbook.io/yq/)
- [aws cli](https://aws.amazon.com/cli/)

## All In one

The following will create eks cluster named `mycluster` in the aws region `us-east-1`. allso deploy efs provisioner and create a storage class named `aws-efs`

```console
./setup-eks-with-sc.sh mycluster us-east-1
```

The following command will delte the eks cluster

```console
./delete-cluster mycluster us-east-1
```

## Just create EFS provisioner and storage class 

if you have already a cluster in eks, you should be able to create efs provisioner and storage class using `kustomize` by referencing to the [resources](./resources) directory

follow this link to setup **EFS** file system first using [EFS Creation](https://github.com/kubernetes-incubator/external-storage/tree/master/aws/efs#prerequisites)

Make a place to work

```console
DEMO_HOME=$(mktemp -d)
```

create a patch file

```console
cat <<EOF >$DEMO_HOME/patch.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: not-important
data:
  fileSystemId: EFS_FILE_SYSTEM_ID_BEEN_CREATED_ABOVE
  efsRegion: AWS_REGION
EOF
```

define a kustomization file that specifies your patch.

```console
cat <<EOF >$DEMO_HOME/kustomization.yaml
resources:
- github.com/ffoysal/efs-provisioner//resources
patches:
- path: patch.yaml
  target:
    kind: ConfigMap
    name: efs-provisioner-configs
EOF
```

then run kustomize

```console
kustomize build $DEMO_HOME | kubectl apply -f -
```
