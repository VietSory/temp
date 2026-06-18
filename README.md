# W10 Labs - External Secrets, Supply Chain Security và Payments Challenge

## 1. Tổng quan

Repo này triển khai các phần chính của W10:

1. **Lab 2.1 - External Secrets Operator**

   * Cài External Secrets Operator bằng GitOps.
   * Đồng bộ secret từ `SecretStore`/`ExternalSecret` sang Kubernetes Secret.
   * Kiểm chứng xoay vòng secret mà pod không cần restart.

2. **Lab 2.2 - Supply Chain Security**

   * Build image bằng GitHub Actions.
   * Scan CVE bằng Trivy.
   * Ký image bằng Cosign.
   * Admission control kiểm tra chữ ký image bằng Sigstore policy-controller.
   * Image chưa ký bị chặn khi deploy vào namespace được enforce.

3. **Payments Challenge - Onboard team B bằng GitOps**

   * Tạo namespace riêng `payments`.
   * Áp RBAC cô lập trong namespace.
   * Áp ResourceQuota và LimitRange.
   * Áp NetworkPolicy để cô lập traffic giữa `payments` và `demo`.
   * Deploy workload team B qua ArgoCD.
   * Chứng minh guardrail cũ của platform tự áp dụng cho team B.

## 2. Thông tin môi trường

* Repo: `https://github.com/VietSory/temp.git`
* Branch: `lab-2-1-eso`
* Kubernetes context/profile: `w10`
* Namespace team A/app cũ: `demo`
* Namespace team B/challenge: `payments`
* ArgoCD namespace: `argocd`
* Argo Rollouts namespace: `argo-rollouts`
* Policy-controller namespace: `cosign-system`
* Gatekeeper namespace: `gatekeeper-system`
* External Secrets namespace: `external-secrets`

Image chính:

```text
ghcr.io/vietsory/w10-api:e74ceb2f257357ba989dd3165c88603a74bad782
```

Digest image từng dùng trong live deployment:

```text
sha256:dc5a780a616ec06b965f402c59f939fb504038670901f2c05da6797137623681
```

## 3. Kiến trúc tổng thể

Luồng tổng thể của project:

```text
Developer push code
        |
        v
GitHub Actions
  - build Docker image
  - Trivy scan CVE
  - Cosign sign image
  - push image lên GHCR
        |
        v
Git repo chứa Kubernetes manifests
        |
        v
ArgoCD root Application
        |
        +--> External Secrets Operator
        +--> ESO SecretStore/ExternalSecret
        +--> Gatekeeper templates/constraints
        +--> Sigstore policy-controller
        +--> ClusterImagePolicy
        +--> demo app
        +--> payments tenant controls
        +--> payments app
        |
        v
Kubernetes cluster w10
  - Calico enforce NetworkPolicy
  - Gatekeeper enforce policy
  - policy-controller verify image signature
```

## 4. Cấu trúc thư mục và tác dụng

### 4.1 Root repo

```text
.
├── .github/workflows/
├── argocd/apps/
├── apps/payments/
├── eso/
├── evidence/
├── policies/
├── policy-bootstrap/
├── rbac/
├── runbooks/
├── signing/
├── src/api/
├── tenants/payments/
├── app.py
├── Dockerfile
├── README.md
└── trivy-fail-trigger.txt
```

Ý nghĩa:

| Path                     | Tác dụng                                                                                                          |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/`     | Chứa GitHub Actions workflow để build, scan, sign và push image.                                                  |
| `argocd/apps/`           | Chứa các ArgoCD `Application` dùng để bootstrap toàn bộ platform và workload bằng GitOps.                         |
| `apps/payments/`         | Chứa manifest workload của team B, ví dụ Deployment/Service `payments-api`.                                       |
| `eso/`                   | Chứa cấu hình External Secrets Operator, `SecretStore` và `ExternalSecret`.                                       |
| `evidence/`              | Chứa log chứng minh kết quả lab/challenge.                                                                        |
| `policies/`              | Chứa policy liên quan tới admission/image verification.                                                           |
| `policy-bootstrap/`      | Chứa phần bootstrap policy ban đầu nếu có dependency theo thứ tự sync.                                            |
| `rbac/`                  | Chứa RBAC dùng cho lab/platform.                                                                                  |
| `runbooks/`              | Chứa runbook vận hành và ADR ngoại lệ CVE.                                                                        |
| `signing/`               | Chứa public key Cosign. Không chứa private key.                                                                   |
| `src/api/`               | Source/API layout phụ hoặc cũ trong repo. Hiện workflow build chính đang dùng root `app.py` và root `Dockerfile`. |
| `tenants/payments/`      | Chứa toàn bộ control của tenant `payments`: namespace, RBAC, quota, limit, network policy.                        |
| `app.py`                 | Source app chính đang được root `Dockerfile` dùng để build image trong workflow.                                  |
| `Dockerfile`             | Dockerfile chính đang được GitHub Actions build bằng `docker build -t "$IMAGE" .`.                                |
| `README.md`              | Tài liệu tổng hợp kiến trúc, cách làm và evidence.                                                                |
| `trivy-fail-trigger.txt` | File phục vụ kiểm thử workflow/Trivy fail scenario.                                                               |

## 5. Các file quan trọng

### 5.1 GitHub Actions

Path chính:

```text
.github/workflows/build-push.yml
```

Tác dụng:

* Trigger workflow khi thay đổi code/build inputs.
* Build Docker image từ root repo.
* Chạy Trivy scan để phát hiện CVE.
* Fail pipeline nếu có CVE mức HIGH/CRITICAL theo cấu hình lab.
* Push image lên GHCR.
* Ký image bằng Cosign.
* Dùng public key trong repo để verify lại hoặc để policy-controller dùng khi admission.

Workflow hiện build từ root repo bằng logic tương đương:

```text
docker build -t "${IMAGE}" .
```

Vì vậy root `Dockerfile` và root `app.py` là file đang được CI sử dụng. Không xóa hai file này nếu chưa đổi workflow sang `src/api`.

### 5.2 Image signing

Path chính:

```text
signing/cosign.pub
```

Tác dụng:

* Chứa Cosign public key.
* Được commit vào repo.
* Dùng để policy-controller verify image signature.

Không được commit:

```text
cosign.key
```

Lý do:

* `cosign.key` là private key.
* Nếu private key bị commit, bất kỳ ai có key đều có thể ký image giả mạo.
* Repo chỉ được chứa public key `cosign.pub`.

### 5.3 ArgoCD Applications

Path chính:

```text
argocd/apps/
```

Các Application quan trọng:

| File                                      | Tác dụng                                         |
| ----------------------------------------- | ------------------------------------------------ |
| `argocd/apps/app-api.yaml`                | Deploy app chính ở namespace `demo`.             |
| `argocd/apps/payments.yaml`               | Deploy tenant controls của namespace `payments`. |
| `argocd/apps/payments-app.yaml`           | Deploy workload `payments-api` của team B.       |
| `argocd/apps/eso.yaml`                    | Cài External Secrets Operator.                   |
| `argocd/apps/eso-config.yaml`             | Apply cấu hình `SecretStore`/`ExternalSecret`.   |
| `argocd/apps/policy-controller.yaml`      | Cài Sigstore policy-controller.                  |
| `argocd/apps/policies.yaml`               | Apply policy verify chữ ký image.                |
| `argocd/apps/gatekeeper.yaml`             | Cài Gatekeeper.                                  |
| `argocd/apps/gatekeeper-templates.yaml`   | Apply ConstraintTemplate.                        |
| `argocd/apps/gatekeeper-constraints.yaml` | Apply Constraint.                                |
| `argocd/apps/k8s-rollout.yaml`            | Cài Argo Rollouts controller và CRDs.            |

Lưu ý:

* Chỉ nên có một Application tên `argo-rollouts`.
* File đúng là `argocd/apps/k8s-rollout.yaml`.
* Không nên giữ thêm file duplicate `argocd/apps/argo-rollouts.yaml` nếu nó cũng định nghĩa `metadata.name: argo-rollouts`.

### 5.4 External Secrets Operator

Path chính:

```text
eso/
```

Tác dụng:

* Cấu hình `SecretStore`.
* Cấu hình `ExternalSecret`.
* Đồng bộ secret vào Kubernetes Secret trong namespace `demo`.
* Cho phép rotate secret mà không commit secret thật vào Git.
* Pod đọc secret qua mounted file nên có thể nhận secret mới mà không restart.

Kết quả mong muốn:

```text
SecretStore tồn tại
ExternalSecret synced
Kubernetes Secret db-secret tồn tại
Pod đọc được secret mới qua mounted volume
```

### 5.5 Gatekeeper policies

Các path chính:

```text
templates/
policies/
policy-bootstrap/
```

Các template/policy đã thấy trong repo:

```text
deployment-replica-limit-template.yaml
disallow-host-network-template.yaml
disallow-latest-tag-template.yaml
disallow-root-user-template.yaml
required-limits-template.yaml
```

Tác dụng:

* Chặn deployment sai chuẩn.
* Chặn `hostNetwork`.
* Chặn image tag `latest`.
* Chặn container chạy root nếu policy yêu cầu.
* Bắt buộc khai báo resource limits.
* Áp dụng guardrail ở cấp cluster thông qua admission control.

### 5.6 RBAC platform

Path chính:

```text
rbac/
```

Các file:

```text
rbac/roles.yaml
rbac/rolebindings.yaml
```

Tác dụng:

* Khai báo Role và RoleBinding cần cho lab/platform.
* Dùng RBAC namespace-scoped thay vì cấp quyền quá rộng ở cấp cluster.

### 5.7 Runbooks

Path chính:

```text
runbooks/
```

Các file:

```text
runbooks/01-secret-rotation.md
runbooks/02-supply-chain-incident.md
runbooks/ADR-0001-cve-exception.md
```

Tác dụng từng file:

| File                          | Tác dụng                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `01-secret-rotation.md`       | Runbook xoay vòng secret bằng ESO, cách kiểm tra sync và rollback.                               |
| `02-supply-chain-incident.md` | Runbook xử lý sự cố supply chain: Trivy fail, unsigned image, policy-controller reject.          |
| `ADR-0001-cve-exception.md`   | ADR mô tả quy trình xin ngoại lệ CVE có thời hạn, có owner, ngày review và kế hoạch gỡ ngoại lệ. |

## 6. Lab 2.1 - External Secrets Operator

Đã triển khai:

* External Secrets Operator bằng GitOps.
* `SecretStore` và `ExternalSecret`.
* Kubernetes Secret `db-secret` trong namespace `demo`.
* Secret rotation.
* Pod đọc secret qua mounted volume.
* Không commit secret thật.

Luồng hoạt động:

```text
ExternalSecret
    |
    v
SecretStore
    |
    v
External Secrets Operator
    |
    v
Kubernetes Secret db-secret
    |
    v
Pod mount secret dưới dạng file
```

Điểm quan trọng:

* Kubernetes Secret chỉ là object trong cluster, không nên commit secret thật vào Git.
* ESO cho phép tách secret value ra khỏi manifest.
* Khi secret được rotate, ESO sync lại Kubernetes Secret.
* Pod mount secret qua volume có thể thấy nội dung mới mà không cần restart.

## 7. Lab 2.2 - Supply Chain Security

Đã triển khai:

* GitHub Actions build image.
* Trivy scan image.
* Cosign ký image.
* Public key commit tại `signing/cosign.pub`.
* Private key `cosign.key` không commit.
* policy-controller verify image signature tại admission.
* Signed image được admit.
* Unsigned image bị reject.

Luồng supply chain:

```text
Code push
   |
   v
GitHub Actions
   |
   +--> docker build
   +--> Trivy scan
   +--> Cosign sign
   +--> push GHCR
   |
   v
ArgoCD deploy manifest
   |
   v
Kubernetes admission
   |
   +--> Gatekeeper kiểm tra policy
   +--> policy-controller verify signature
   |
   v
Pod được tạo nếu pass toàn bộ guardrail
```

Image hợp lệ:

```text
ghcr.io/vietsory/w10-api:e74ceb2f257357ba989dd3165c88603a74bad782
```

Image không hợp lệ để test:

```text
nginx:1.27-alpine
```

Kết quả mong muốn:

```text
Signed image: admitted
Unsigned image: rejected by policy.sigstore.dev
```

## 8. Payments Challenge - Onboard team B bằng GitOps

Challenge này onboard team B vào namespace riêng tên `payments`. Team A/app cũ vẫn nằm trong namespace `demo`.

Toàn bộ resource của tenant `payments` được quản lý bằng GitOps thông qua ArgoCD.

Manifest chính:

```text
tenants/payments/
apps/payments/
argocd/apps/payments.yaml
argocd/apps/payments-app.yaml
```

### 8.1 Mục tiêu

Mục tiêu là chứng minh team B có một “phòng riêng” trong cluster:

* Có namespace riêng `payments`.
* Có RBAC giới hạn trong namespace.
* Có quota và default resources để tránh workload dùng quá tài nguyên.
* Có NetworkPolicy cô lập traffic giữa `payments` và `demo`.
* Workload của team B vẫn đi qua guardrail cũ của platform.
* Tất cả được triển khai bằng GitOps.

### 8.2 Namespace

Namespace cuối cùng dùng cho challenge là:

```text
payments
```

Namespace `payments` được tạo bằng GitOps và có label:

```text
policy.sigstore.dev/include=true
```

Tác dụng của label:

* Bật Sigstore policy-controller cho namespace `payments`.
* Mọi pod trong namespace này phải dùng image có chữ ký hợp lệ.
* Image chưa ký hoặc ký không đúng key sẽ bị admission reject.

### 8.3 RBAC

Tenant `payments` dùng RBAC giới hạn trong namespace:

```text
ServiceAccount: payments-dev-sa
Role: payments-dev-role
RoleBinding: payments-dev-rolebinding
```

Thiết kế này cố tình không dùng `ClusterRoleBinding`.

Lý do:

* `Role` định nghĩa quyền trong một namespace cụ thể.
* `RoleBinding` gắn quyền đó cho ServiceAccount trong namespace đó.
* `ClusterRoleBinding` có thể cấp quyền ở phạm vi toàn cluster.
* Nếu dùng `ClusterRoleBinding` cho tenant, ServiceAccount của team B có thể với sang resource của namespace khác, ví dụ `demo`.
* Điều đó phá vỡ yêu cầu cô lập tenant.

Evidence mới:

```text
evidence/11-rbac-real-forbidden-proof.log
```

Evidence này có:

* YAML live của Role.
* YAML live của RoleBinding.
* Lệnh `kubectl auth can-i`.
* Lệnh thật chạy dưới identity `system:serviceaccount:payments:payments-dev-sa`.
* Output `Forbidden` khi ServiceAccount cố truy cập `demo`, đọc secret, tạo rolebinding hoặc tạo clusterrolebinding.

Kết quả đã kiểm chứng:

```text
payments-dev-sa list pods trong payments: yes
payments-dev-sa get pods trong payments: allowed
payments-dev-sa list pods trong demo: no
payments-dev-sa get pods trong demo: Forbidden
payments-dev-sa get secrets trong payments: Forbidden
payments-dev-sa create rolebindings trong payments: Forbidden
payments-dev-sa create clusterrolebindings: Forbidden
```

### 8.4 ResourceQuota và LimitRange

Namespace `payments` có một `ResourceQuota` và một `LimitRange`.

ResourceQuota:

```text
payments-quota
```

LimitRange:

```text
payments-default-limits
```

Mục đích:

* `ResourceQuota` giới hạn tổng tài nguyên mà namespace `payments` được dùng.
* `LimitRange` đặt request/limit mặc định cho pod thiếu khai báo resources.
* Pod vượt quota bị Kubernetes reject.
* Pod thiếu resources được inject default CPU/memory request và limit.

Evidence mới:

```text
evidence/12-quota-limitrange-real-proof.log
```

Evidence này có:

* YAML live của `ResourceQuota`.
* YAML live của `LimitRange`.
* Manifest pod cố tình vượt quota.
* Output thật `exceeded quota`.
* Manifest pod thiếu resources.
* Output thật cho thấy Kubernetes inject default resources.

Kết quả đã kiểm chứng:

```text
Pod vượt quota bị reject với lỗi exceeded quota.
Pod thiếu resources được inject:
limits.cpu=200m
limits.memory=256Mi
requests.cpu=50m
requests.memory=64Mi
```

### 8.5 NetworkPolicy

Cluster `w10` được recreate với Calico CNI để NetworkPolicy được enforce thật.

Namespace `payments` có các NetworkPolicy:

```text
payments-default-deny-ingress
payments-allow-same-ns-ingress
payments-egress-same-ns-and-dns
```

Thiết kế:

1. `payments-default-deny-ingress`

   Chặn traffic đi vào pod trong namespace `payments` theo mặc định.

2. `payments-allow-same-ns-ingress`

   Cho phép pod trong cùng namespace `payments` gọi nhau. Policy này cần thiết để app nội bộ của team B vẫn hoạt động.

3. `payments-egress-same-ns-and-dns`

   Chỉ cho phép egress tới pod cùng namespace và DNS. Điều này chặn pod trong `payments` gọi sang service của namespace khác, ví dụ `demo`.

Lưu ý quan trọng:

Chỉ dùng default-deny ingress là chưa đủ để chặn `payments` gọi sang `demo`, vì đó là chiều egress từ `payments`.

Muốn chặn:

```text
payments -> demo
```

thì phải có NetworkPolicy kiểm soát egress.

Evidence mới:

```text
evidence/13-networkpolicy-real-proof.log
```

Evidence này có:

* Calico pods đang chạy.
* YAML live của NetworkPolicy.
* Service `payments-api` trong namespace `payments`.
* Service `api` trong namespace `demo`.
* Pod test `payments -> payments-api`.
* Pod test `payments -> demo/api`.
* Output thật từ pod test.

Kết quả đã kiểm chứng:

```text
payments -> payments-api: {"ok":true,"version":"payments-v1"}
payments -> demo/api: BLOCKED_OR_TIMEOUT
```

### 8.6 Ứng dụng team B

Ứng dụng team B chạy trong namespace `payments`:

```text
Deployment: payments-api
Service: payments-api
Replicas: 2
```

Image sử dụng là image đã được ký:

```text
ghcr.io/vietsory/w10-api:e74ceb2f257357ba989dd3165c88603a74bad782
```

Evidence runtime:

```text
evidence/10-gitops-runtime-proof.log
evidence/14-supply-chain-real-proof.log
```

Kết quả đã kiểm chứng:

```text
payments-api: 2/2 Running
Service payments-api: ClusterIP
Image: signed image từ GHCR
```

## 9. Vì sao guardrail cũ tự áp dụng cho team B?

Không cần viết lại guardrail riêng cho team B vì các guardrail hiện tại là admission control ở cấp cluster.

Các guardrail như Gatekeeper và Sigstore policy-controller kiểm tra resource tại thời điểm admission. Khi team B deploy workload vào namespace `payments`, workload đó vẫn đi qua cùng admission pipeline của cluster.

Vì vậy:

* Nếu pod thiếu resource limits, Gatekeeper có thể reject.
* Nếu image chưa được ký, policy-controller reject.
* Nếu namespace có label `policy.sigstore.dev/include=true`, policy-controller sẽ kiểm tra chữ ký image trong namespace đó.
* Vì policy chạy ở cấp cluster, team B tự động kế thừa policy cũ khi workload đi qua Kubernetes admission.

Evidence mới:

```text
evidence/14-supply-chain-real-proof.log
```

Kết quả đã kiểm chứng:

```text
Signed image: admitted
Unsigned image nginx:1.27-alpine: rejected
Lỗi có admission webhook "policy.sigstore.dev" denied
Lỗi có no signatures found
```

## 10. Role/RoleBinding khác ClusterRoleBinding ra sao để giữ cô lập?

### Role

`Role` là object RBAC theo namespace.

Ví dụ Role trong namespace `payments` chỉ định nghĩa quyền bên trong namespace `payments`.

### RoleBinding

`RoleBinding` gắn Role với một subject, ví dụ ServiceAccount `payments-dev-sa`.

Nếu RoleBinding nằm trong namespace `payments`, quyền được cấp chỉ có hiệu lực trong namespace đó.

### ClusterRoleBinding

`ClusterRoleBinding` gắn quyền ở phạm vi toàn cluster.

Nếu dùng ClusterRoleBinding cho tenant, ServiceAccount của team B có thể nhận quyền ngoài namespace `payments`. Điều này có thể cho phép team B đọc/sửa resource ở namespace khác, ví dụ `demo`.

Vì vậy challenge dùng:

```text
Role + RoleBinding
```

và không dùng:

```text
ClusterRoleBinding
```

Kết quả kiểm chứng:

```text
payments-dev-sa thao tác trong payments theo quyền được cấp: allowed
payments-dev-sa truy cập demo: Forbidden
payments-dev-sa tạo clusterrolebinding: Forbidden
```

## 11. Evidence

Evidence cuối nằm trong thư mục:

```text
evidence/
```

Bộ evidence chính nên giữ:

```text
evidence/10-gitops-runtime-proof.log
evidence/11-rbac-real-forbidden-proof.log
evidence/12-quota-limitrange-real-proof.log
evidence/13-networkpolicy-real-proof.log
evidence/14-supply-chain-real-proof.log
evidence/99-summary.log
```

Ý nghĩa từng file:

| File                                 | Nội dung chứng minh                                                                                                                                      |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `10-gitops-runtime-proof.log`        | Chứng minh context `w10`, ArgoCD apps, namespace, Calico, payments runtime, demo runtime, tenant controls, ClusterImagePolicy và signed image đang chạy. |
| `11-rbac-real-forbidden-proof.log`   | Chứng minh RBAC bằng lệnh thật dưới identity `payments-dev-sa`, gồm cả allowed trong `payments` và Forbidden khi với sang `demo` hoặc leo quyền.         |
| `12-quota-limitrange-real-proof.log` | Chứng minh ResourceQuota reject pod vượt quota và LimitRange inject default resources.                                                                   |
| `13-networkpolicy-real-proof.log`    | Chứng minh Calico enforce NetworkPolicy, cùng namespace gọi được, cross namespace `payments -> demo` bị timeout/block.                                   |
| `14-supply-chain-real-proof.log`     | Chứng minh signed image được admit và unsigned image bị policy-controller reject.                                                                        |
| `99-summary.log`                     | Tổng hợp các keyword/pass result quan trọng từ toàn bộ evidence.                                                                                         |

Các keyword quan trọng trong evidence:

```text
Forbidden
exceeded quota
payments-v1
BLOCKED_OR_TIMEOUT
SIGNED_IMAGE_ADMITTED
admission webhook "policy.sigstore.dev" denied
no signatures found
```

## 12. Tiêu chí hoàn thành

Project đạt các tiêu chí:

```text
Context: w10
CNI: Calico
Namespace team A: demo
Namespace team B: payments
GitOps: ArgoCD quản lý tenant và workload
RBAC isolation: pass
ResourceQuota: pass
LimitRange: pass
payments -> payments-api: allowed
payments -> demo/api: blocked hoặc timeout
payments-api: running
signed image: admitted
unsigned image: rejected
cosign.key: không commit
runbooks/: đủ 2 runbook + 1 ADR ngoại lệ CVE
```
