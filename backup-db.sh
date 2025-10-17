Backup etcd db
==============
1. Check the manifest for the data directory.
grep data-dir /etc/kubernetes/manifests/etcd.yaml
	- --data-dir=/var/lib/etcd

2. Go into the etcd-master. Why use sh? 
kubectl -n kube-system exec -it etcd-<TAB> -- sh

3. Learn how to use etcdctl. Navigate around. Navigate around. No ls? how to list? <- 2 methods
etcdctl -h
pwd
ls
echo * OR use shell tab completion

4. Get endpoint health. etcdctl_api version  if etcdctl version is < 3.4
kubectl -n kube-system exec -it etcd-cp -- sh \
#Same as before
-c "ETCDCTL_API=3 \ #Version to use
ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \ #Pass the certificate authority
ETCDCTL_CERT=/etc/kubernetes/pki/etcd/server.crt \ #Pass the peer cert and key
ETCDCTL_KEY=/etc/kubernetes/pki/etcd/server.key \
etcdctl endpoint health"

OR
etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
	--cert=/etc/kubernetes/pki/etcd/server.crt \
	--key=/etc/kubernetes/pki/etcd/server.key \
	endpoint health

use history to recall cmd

5. list members
etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
	--cert=/etc/kubernetes/pki/etcd/server.crt \
	--key=/etc/kubernetes/pki/etcd/server.key \
	member list -w table

6. save snapshot
etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
	--cert=/etc/kubernetes/pki/etcd/server.crt \
	--key=/etc/kubernetes/pki/etcd/server.key \
	snapshot save /var/lib/etcd/snapshot.db

7. exit and backup
exit
mkdir $HOME/backup
sudo cp /var/lib/etcd/snapshot.db $HOME/backup/snapshot.db-$(date +%m-%d-%y)
sudo cp /root/kubeadm-config.yaml $HOME/backup/
sudo cp -r /etc/kubernetes/pki/etcd $HOME/backup/

https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster


