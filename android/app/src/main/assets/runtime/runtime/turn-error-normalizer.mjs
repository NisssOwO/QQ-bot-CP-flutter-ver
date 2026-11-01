const CODE_RULES = [
  // A tool that dies without reporting an outcome aborts the whole turn; say that
  // plainly instead of surfacing TOOL_OUTCOME_UNKNOWN to the person in the chat.
  { test: /tooloutcomeunknown|tool.?outcome|tool.?call.*fail/i, code: 'AI_TOOL_UNAVAILABLE', message: '这轮要用联网工具，但它在手机上不可用，所以没有答完。可以再发一次，或换个不用联网的问题。' },
  { test: /401|unauthori[sz]ed|authentication|api.?key/i, code: 'AI_AUTH_FAILED', message: 'AI 接口认证失败，请检查 API Key 是否正确、已保存，并确认它属于当前接口。' },
  { test: /model.*(not found|不存在|invalid)|unknown model|模型.*(不存在|无效)/i, code: 'AI_MODEL_NOT_FOUND', message: '模型名称不可用，请从当前 Base URL 重新拉取模型列表。' },
  { test: /thinking(format|.?level)|reasoning|unsupported.*(parameter|option)|invalid.?config|invalid.?request|400\b/i, code: 'AI_REQUEST_INVALID', message: '当前模型或接口不支持这组请求参数，请重新测试接口或关闭不兼容的思考设置。' },
  { test: /timeout|timed.?out|ETIMEDOUT|MODEL_TIMEOUT/i, code: 'AI_TIMEOUT', message: 'AI 请求超时，请检查网络或稍后重试。' },
  { test: /ECONN|ENET|ENOTFOUND|EAI_AGAIN|connection|transport|network|TLS|socket/i, code: 'AI_NETWORK_ERROR', message: '无法连接 AI 接口，请检查网络、Base URL 和代理设置。' },
];

/** Convert a low-level turn error into a safe, actionable user-facing error. */
export function normalizeTurnError(failure) {
  if (failure === undefined || failure === null) return undefined;
  const rawCode = String(failure.code ?? 'UNKNOWN');
  const rawMessage = String(failure.message ?? 'unknown error');
  const source = `${rawCode} ${rawMessage}`;
  const rule = CODE_RULES.find(candidate => candidate.test.test(source));
  return {
    code: rule?.code ?? `AI_${rawCode.replace(/[^A-Z0-9_]+/gi, '_').toUpperCase() || 'UNKNOWN'}`,
    message: rule ? `${rule.message}（原始错误：${rawCode}）` : `AI 请求失败，请查看日志中的详细错误（${rawCode}）。`,
    rawCode,
  };
}
