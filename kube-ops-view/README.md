Kubernetes Operational View
===========================

Original (repo)[https://codeberg.org/hjacobs/kube-ops-view]

### Installation

Changed configuration for deployment and changed type of service -> to LoadBalancer

First we need to install metric server:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system
```

You can find example Kubernetes manifests for deployment in the `deploy`
folder. It should be as simple as:

``` {.sourceCode .bash}

kubectl apply -k deploy 
kubectl get pod,svc,sa
```

Afterwards you can open \"kube-ops-view\" via kubectl port-forward:

``` {.sourceCode .bash}
$ kubectl port-forward service/kube-ops-view 8080:80
```

