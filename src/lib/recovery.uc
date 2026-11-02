// Recovery consumes confirmed shared health; no additional liveness counter.
import { fresh } from './health.uc';
function recoveryStep(previous, health, enabled, now, leak) {
	let state = previous || { phase: 'healthy', step: 0, next: 0, downtries: 0 };
	if (!enabled) return { phase: 'off', step: 0, next: 0, downtries: 0 };
	if (state.phase == 'off') state = { phase: 'healthy', step: 0, next: 0, downtries: 0 };
	if (!fresh(health, now) && !leak) return state;
	if (!leak && health.https.state == 'up' && health.https.sample == 'success')
		return { phase: 'healthy', step: 0, next: 0, downtries: 0 };
	if ((!leak && (health.https.state != 'down' || health.https.sample != 'failure')) || now < state.next) return state;
	if (state.phase == 'down')
		return { ...state, phase: 'reconnecting', step: 0, action: 'retry', next: now + 45 };
	if (state.step < 4)
		return { ...state, phase: 'reconnecting', step: state.step + 1, action: '' + state.step, next: now + 45 };
	let tries = state.downtries + 1;
	return { phase: 'down', step: 0, downtries: tries, action: 'stop', next: now + min(600, (60 << min(tries - 1, 4))) };
}
export { recoveryStep };
