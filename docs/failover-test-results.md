# Failover Test Results

**Date:** 2026-07-24
**Method:** Hard termination of one ASG instance via `aws ec2 terminate-instances`

## Timeline

| Time (BST) | Event |
|---|---|
| 21:12:28 | Instance `i-0023654c41acd8094` terminated manually to simulate failure |
| 21:13:33–21:26:41 | Baseline: steady `302` responses via ALB |
| 21:26:46–21:27:02 | ALB returns `504` (Gateway Timeout) — no healthy target available |
| 21:27:17 | Service restored — surviving instance `i-0eeb949e60212f5f7` continued serving traffic |
| ~2–3 min later | ASG launched replacement instance `i-0b83ad28dc1d6e63f`, reached `InService`/`Healthy` |

## Result

Total observed downtime: ~30 seconds (two failed health-check-interval requests).
ASG automatically replaced the terminated instance with zero manual intervention.
Target group returned to 2/2 healthy within ~3 minutes of the failure.

## Conclusion

Confirms `health_check_type = "ELB"` + Auto Scaling Group correctly detects and
recovers from instance failure without manual intervention, meeting the
project's high-availability requirement.
