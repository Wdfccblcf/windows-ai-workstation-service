## PR 类型

- [ ] Spec（纯规格，不含实现）
- [ ] Impl（基于已合并 Spec）
- [ ] Revert（关联独立回滚 Issue/Spec）
- [ ] Docs（不改变运行时行为）

## 关联与基线

- Linked Issue：
- Linked Spec：
- 创建时 `origin/main` SHA：
- Final head SHA：

## 为什么改

说明问题证据、预期收益和为什么现在处理。

## 变更与非目标

列出实际修改、文件/设置边界，以及本 PR 明确不处理的相邻事项。

## Plan / implementation 对照

逐项对应 Issue/Spec 计划，说明实现结果和任何经验证的偏差。

## 验证证据

- 本地 check/test：
- Fresh install / fresh clone：
- Windows PowerShell 生产契约：
- PR Quality / Pages / CodeQL：
- Main CI / deployment / online smoke（合并后回写）：

## 安全、隐私与发布影响

- [ ] 未提交真实凭据、客户数据、完整用户路径或未脱敏日志/截图。
- [ ] 已说明依赖、实时设置、workflow 权限和 CodeQL/Ruleset 影响。
- [ ] 已说明生产脚本、ZIP、checksum 与 SHA256 是否变化。
- [ ] 若涉及敏感漏洞，细节只存在于私密报告中。

## 风险与回滚

写明失败信号、停止条件、回滚顺序和回滚后验证。

## Final checklist

- [ ] Issue → Spec PR → Impl PR 顺序正确，且各分支来自当时最新 `origin/main`。
- [ ] Spec PR 未混入实现；Impl PR 关联已合并 Spec。
- [ ] 所有 required checks、CodeQL 与 review threads 已完成。
- [ ] 以固定 final head 合并，没有 bypass、force push 或直接 push `main`。
- [ ] Issue 验收 checklist、run/deployment/hash 证据和关闭原因已回写。
