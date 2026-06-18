## Payments Challenge - Onboard team B bằng GitOps

Challenge này onboard team B vào namespace riêng tên `payments`. Team A/app cũ vẫn nằm trong namespace `demo`.

Toàn bộ resource của tenant `payments` được quản lý bằng GitOps thông qua ArgoCD. Repo chứa manifest tenant tại:

```text
tenants/payments/
apps/payments/
argocd/apps/payments.yaml
argocd/apps/payments-app.yaml
```

### Mục tiêu

Mục tiêu là chứng minh team B có một “phòng riêng” trong cluster:

* Có namespace riêng `payments`.
* Có RBAC giới hạn trong namespace.
* Có quota và default resources để tránh workload dùng quá tài nguyên.
* Có NetworkPolicy cô lập traffic giữa `payments` và `demo`.
* Workload của team B vẫn đi qua guardrail cũ của platform, gồm admission policy và image signature verification.
* Tất cả được triển khai bằng GitOps.

## Namespace

Namespace cuối cùng dùng cho challenge là:

```text
payments
```

Namespace này được tạo sớm bằng GitOps để các resource tenant khác có thể trỏ vào đúng namespace.

Namespace `payments` có label:

```text
policy.sigstore.dev/include=true
```

Label này làm cho Sigstore policy-controller áp dụng kiểm tra chữ ký image với workload trong namespace `payments`.

## RBAC

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
* Nếu dùng `ClusterRoleBinding` cho tenant, ServiceAccount của team B có thể với sang resource của namespace khác, ví dụ `demo`, và phá vỡ yêu cầu cô lập tenant.

Evidence:

```text
evidence/01-rbac-isolation.log
```

Kết quả đã kiểm chứng:

```text
payments-dev-sa list pods trong payments: yes
payments-dev-sa list pods trong demo: no
payments-dev-sa get secrets trong payments: no
payments-dev-sa create rolebindings trong payments: no
payments-dev-sa create clusterrolebindings: no
```

## ResourceQuota và LimitRange

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

Evidence:

```text
evidence/02-quota-violation.log
evidence/03-limitrange-default.log
```

Kết quả đã kiểm chứng:

```text
Pod vượt quota bị reject với lỗi exceeded quota.
Pod thiếu resources được inject:
limits.cpu=200m
limits.memory=256Mi
requests.cpu=50m
requests.memory=64Mi
```

## NetworkPolicy

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

Chỉ dùng default-deny ingress là chưa đủ để chặn `payments` gọi sang `demo`, vì đó là chiều egress từ `payments`. Muốn chặn `payments -> demo`, phải có NetworkPolicy kiểm soát egress.

Evidence:

```text
evidence/05-netpol-same-namespace-allowed.log
evidence/06-netpol-cross-namespace-blocked.log
```

Kết quả đã kiểm chứng:

```text
payments -> payments-api: {"ok":true,"version":"payments-v1"}
payments -> demo/api: BLOCKED_OR_TIMEOUT
```

## Ứng dụng team B

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

Evidence:

```text
evidence/04-payments-app-health.log
```

Kết quả đã kiểm chứng:

```text
payments-api: 2/2 Running
Service payments-api: ClusterIP
Image: signed image từ GHCR
```

## Guardrail cũ tự áp dụng cho team B

Không cần viết lại guardrail riêng cho team B vì các guardrail hiện tại là admission control ở cấp cluster.

Các guardrail như Gatekeeper và Sigstore policy-controller kiểm tra resource tại thời điểm admission. Khi team B deploy workload vào namespace `payments`, workload đó vẫn đi qua cùng admission pipeline của cluster.

Vì vậy:

* Nếu pod thiếu resource limits, Gatekeeper có thể reject.
* Nếu image chưa được ký, policy-controller reject.
* Nếu namespace có label `policy.sigstore.dev/include=true`, policy-controller sẽ kiểm tra chữ ký image trong namespace đó.

Evidence:

```text
evidence/07-unsigned-image-rejected.log
```

Kết quả đã kiểm chứng:

```text
Pod dùng image unsigned nginx:1.27-alpine bị reject.
Lỗi có admission webhook "policy.sigstore.dev" denied.
Lỗi có no signatures found.
```

## Tổng hợp evidence

Evidence cuối nằm trong thư mục:

```text
evidence/
```

Các file chính:

```text
evidence/00-final-runtime-check.log
evidence/01-rbac-isolation.log
evidence/02-quota-violation.log
evidence/03-limitrange-default.log
evidence/04-payments-app-health.log
evidence/05-netpol-same-namespace-allowed.log
evidence/06-netpol-cross-namespace-blocked.log
evidence/07-unsigned-image-rejected.log
evidence/99-summary.log
```

Tiêu chí hoàn thành:

```text
Context: w10
CNI: Calico
Namespace team A: demo
Namespace team B: payments
RBAC isolation: pass
ResourceQuota: pass
LimitRange: pass
payments -> payments-api: allowed
payments -> demo/api: blocked hoặc timeout
payments-api: running
unsigned image: rejected
GitOps Applications: healthy
cosign.key: không commit
runbooks/: đủ 2 runbook + 1 ADR ngoại lệ CVE
```
