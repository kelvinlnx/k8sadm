CPU and Memory Hogger
=====================
1. Create container named stress.
kubectl create deployment hog --image vish/stress

2. Check deployment
kubectl get deployments
kubectl describe deployment hog
kubectl get deployment hog -o yaml

3. Add limits
kubectl get deployment hog -o yaml > hog.yaml
vi hog.yaml
	imagePullPolicy: Always
	  name: hog
	  resources:
	    limits:
	      memory: "4Gi"
	    requests:
	      memory: "2500Mi"
	  terminationMessagePath: /dev/termination-log
          terminationMessagePolicy: File
kubectl replace -f hog.yaml

4. Check
kubectl get deployment hog -o yaml
kubectl get po
kubectl logs hog-64cbfcc7cf-lwq66

5. monitor from another terminal with top.

6. modify
resources:
  limits:
    cpu: "1"
    memory: "4Gi"
  requests:
    cpu: "0.5"
    memory: "500Mi"
args:
- -cpus
- "2"
- -mem-total
- "950Mi"
- -mem-alloc-size
- "100Mi"
- -mem-alloc-sleep
- "1s"

7. apply file

8. check if error check logs.

Namespace resource limits
=========================
kubectl create namespace low-usage-limit
kubectl get namespace
cat low-range.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: low_limit_range
spec:
  limits:
  - default:
      cpu: 1
      memory: 500Mi
    defaultRequest:
      cpu: 0.5
      memory: 100Mi
    type: Container

kubectl create -f low-resource-range.yaml -n low-usage-limit
kubectl get LimitRange
kubectl get LimitRange --all-namespaces
kubectl -n low-usage-limit \
create deployment limited-hog --image vish/stress
kubectl get deployments --all-namespaces
kubectl -n low-usage-limit delete deployment hog limited-hog
kubectl delete deployment hog
created in second node. due to stress on node.

