# Runbook 02 - Xu ly su co supply chain

Muc tieu:
- Xu ly khi Trivy fail vi CVE HIGH/CRITICAL.
- Xu ly khi image thieu chu ky Cosign.
- Xu ly khi policy-controller reject workload.

Pham vi:
- Repo: https://github.com/VietSory/temp.git
- Branch: lab-2-1-eso
- Image: ghcr.io/vietsory/w10-api
- Public key: signing/cosign.pub
- Admission policy: require-cosign-signature

Tinh huong 1 - Trivy fail vi CVE HIGH/CRITICAL:
Kiem tra workflow:
$ gh run list --repo VietSory/temp --limit 10

Xem log:
$ gh run view --repo VietSory/temp <RUN_ID> --log

Xu ly:
1. Doc CVE va package bi loi trong log Trivy.
2. Nang base image hoac dependency.
3. Chay lai workflow build-push.
4. Chi deploy image sau khi Trivy pass.

Kiem chung:
$ gh run list --repo VietSory/temp --workflow build-push.yml --limit 3

Ket qua ky vong:
- Workflow success.
- Image moi duoc build, scan, push, sign, verify.

Tinh huong 2 - Admission reject vi image chua ky:
Trieu chung:
- admission webhook "policy.sigstore.dev" denied the request
- no signatures found

Kiem tra namespace enforce:
$ kubectl get ns demo payments --show-labels

Kiem tra ClusterImagePolicy:
$ kubectl get clusterimagepolicy
$ kubectl get clusterimagepolicy require-cosign-signature -o yaml

Kiem tra policy-controller logs:
$ kubectl logs -n cosign-system -l app.kubernetes.io/name=policy-controller --tail=200

Kiem tra image dang chay:
$ kubectl get rollout api -n demo -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
$ kubectl get deploy payments-api -n payments -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

Verify chu ky local:
$ cosign verify --key signing/cosign.pub <IMAGE>

Xu ly:
1. Chay lai workflow build-push.
2. Dam bao step Cosign sign thanh cong.
3. Deploy dung image da ky.
4. Test lai admission.

Tinh huong 3 - Local cosign verify pass nhung policy-controller bao no signatures found:
Xu ly:
1. Kiem tra version Cosign trong CI.
2. Dung Cosign v2 neu policy-controller hien tai khong tuong thich voi signature format moi.
3. Build/sign lai image.
4. Deploy lai image moi.

Kiem chung hoi phuc:
Signed image phai duoc admit:
$ POD="$(kubectl get pod -n demo -l app=api -o jsonpath='{.items[0].metadata.name}')"
$ kubectl delete pod -n demo "$POD"
$ kubectl argo rollouts status api -n demo --timeout=180s

Unsigned image phai bi reject:
$ kubectl apply -f /tmp/payments-unsigned-nginx.yaml

Ket qua ky vong:
- admission webhook "policy.sigstore.dev" denied
- no signatures found
