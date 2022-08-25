# karpenter-demo
Check what karpenter can do

Auth by ssh key 

To clone repo need 

```bash
git clone git@github.com:vedmichv/karpenter-demo.git
```

## Demo time

### Randmon load 
We are going to run 5000pods batch 500pod. On the start of the session. 

```bash
cd generate-load
./create.workload.sh 5000 500
```

### Karpenter load 

100vCPU -> 400 Pods

```bash
command
```

100vCPU -> 100 Pods

```bash
command
```

100vCPU -> 10 Pods

```bash
command
```

### Kubernetes Cluster Autoscaler

100vCPU -> 400 Pods 

```bash
command
```

100vCPU -> 100 Pods

```bash
command
```

100vCPU -> 10 Pods

```bash
command
```

### Custom configuratio for Karpenter


Again run 100vCPU -> 400 Pods, and scale down deployment to 100 pods

```bash
command
```

Apply skrew for pods


### Test when we confugure karpenter 
- max pods
- auto spread - reduce the cound of 