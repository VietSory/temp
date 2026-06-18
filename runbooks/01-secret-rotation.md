# Runbook 01 - Xoay vong secret bang ESO

Muc tieu:
- Xoay secret do External Secrets Operator quan ly.
- Xac minh Kubernetes Secret duoc cap nhat.
- Xac minh app doc duoc secret moi ma khong restart pod.

Pham vi:
- Namespace: demo
- SecretStore: fake-store
- ExternalSecret: db-creds
- Kubernetes Secret: db-secret
- App: api

Kiem tra truoc:
$ kubectl get application external-secrets eso-config api -n argocd
$ kubectl get secretstore -n demo
$ kubectl get externalsecret -n demo

Quy trinh xoay secret:
1. Sua gia tri secret trong manifest ESO.
$ grep -R "password" -n eso

2. Commit va push thay doi.
$ git add eso
$ git commit -m "ops: rotate demo db secret"
$ git push origin lab-2-1-eso

3. Refresh ArgoCD.
$ kubectl annotate application eso-config -n argocd argocd.argoproj.io/refresh=hard --overwrite

Kiem chung:
$ kubectl get externalsecret db-creds -n demo
$ kubectl describe externalsecret db-creds -n demo

Kiem tra secret da sync:
$ kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d
$ echo

Kiem tra pod doc secret moi:
$ POD="$(kubectl get pod -n demo -l app=api -o jsonpath='{.items[0].metadata.name}')"
$ kubectl exec -n demo "$POD" -- cat /etc/db-secret/password

Kiem tra pod khong restart:
$ kubectl get pod -n demo "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'

Ket qua ky vong:
- ExternalSecret synced.
- db-secret co gia tri moi.
- Pod doc duoc gia tri moi tu mounted file.
- restartCount khong tang.

Rollback:
$ git revert HEAD
$ git push origin lab-2-1-eso
$ kubectl annotate application eso-config -n argocd argocd.argoproj.io/refresh=hard --overwrite

Ghi chu:
- Khong commit secret that.
- Lab nay dung ESO fake provider de mo phong quy trinh.
