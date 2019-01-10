# k8s-lab
k8s 一些验证试验

### kubecert.sh
k8s webhook 需要通过 https 的方式请求 service，折腾了一天，发现证书签发有各种各样问题，好在后面搞懂了，顺便写了个脚本方便日后使用。

```bash

Usage:
    kubecert.sh get cabundle
    kubecert.sh create secret
Examples:
    kubecert.sh get cabundle                               get cabundle from k8s cluster.
    kubecert.sh create secret svc-example                  create secret svc-example on default namespace,key.pem and cert.pem include in secret svc-example-secret.
    kubecert.sh create secret svc-example kube-system      create secret svc-example on kube-system namespace,key.pen and cert.pen.
    
```
