
sudo chown ubuntu:ubuntu ~/resources

install helm,
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

#1-  install ebs 
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver

helm install aws-ebs-csi-driver \
    aws-ebs-csi-driver/aws-ebs-csi-driver \
    -n kube-system 

kubectl apply -f resources/storageclass.yaml


create aebs-test.yaml file and apply it


Volume Mount

Exec into the pod and verify the /data mount:

kubectl exec -n ebs-test -it <pod-name> -- sh
ls /data
cat /data/test.txt



steps for CloudNativePG operator manifest


kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.28/releases/cnpg-1.28.1.yaml
This installs the operator into the cnpg-system namespace.


Verify:

kubectl get pods -n cnpg-system



second option  optional for now --- ya abi check ni kiya mana.
Install via Helm (Recommended for Flexibility)
If you prefer Helm:

bash
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update
helm install cnpg cnpg/cloudnative-pg --namespace cnpg-system --create-namespace
Helm lets you customize values (like namespaces, RBAC, monitoring) more easily.



spin up a highly available PostgreSQL cluster on Kubernetes with CloudNativePG


kubectl apply -f postgres-ha.yaml
kubectl get pods -n postgres-ha
kubectl get pvc -n postgres-ha
kubectl get svc -n postgres-ha


✅ Connect to PostgreSQL
Inside the cluster:

kubectl exec -n postgres-ha -it ha-postgres-1 -- psql -U postgres

Run:

SELECT version();
SELECT * FROM pg_stat_replication;


⚡ Test High Availability

Delete the primary pod:
kubectl delete pod ha-postgres-1 -n postgres-ha


CloudNativePG will automatically promote one of the replicas to primary.
Check again:
kubectl get pods -n postgres-ha

To know whether the pod you deleted was primary or secondary,
kubectl get pods -n postgres-ha --show-labels
