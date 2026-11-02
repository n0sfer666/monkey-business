import { DEFAULT_TARGETS, normalizeTargets } from '../lib/availability-settings.uc';
import { fingerprint } from './fingerprint.uc';
import { CONFIG } from './paths.uc';
import { acquireMutation } from './mutation.uc';

function availabilitySettings(freshCursor) {
	function get() {
		let cursor = freshCursor(), targets = [];
		for (let i = 0; i < 2; i++) {
			let url = cursor.get(CONFIG, 'availability', 'target' + (i + 1) + '_url');
			let code = cursor.get(CONFIG, 'availability', 'target' + (i + 1) + '_status');
			push(targets, { url: url != null ? url : DEFAULT_TARGETS[i].url,
				expected_status: code != null ? int(code) : DEFAULT_TARGETS[i].expected_status });
		}
		let checked = normalizeTargets(targets);
		if (length(checked.errors)) return { error: 'invalid_availability_settings' };
		return { api_version: 2, targets: checked.targets, revision: fingerprint(checked.targets) };
	}
	function apply(args) {
		if (type(args) != 'object' || type(args.expected_revision) != 'string') return { error: 'invalid_request' };
		let checked = normalizeTargets(args.targets);
		if (length(checked.errors)) return { error: 'invalid_targets', items: checked.errors };
		let lock = acquireMutation();
		if (lock == null) return { error: 'busy' };
		let result;
		try {
			let before = get();
			if (before.error != null) result = before;
			else if (before.revision != args.expected_revision) result = { error: 'revision_conflict' };
			else {
				let cursor = freshCursor();
				let type_ = cursor.get(CONFIG, 'availability');
				if (type_ != null && type_ != 'availability') result = { error: 'section_id_conflict' };
				else if (sprintf('%J', before.targets) == sprintf('%J', checked.targets)) result = before;
				else {
					cursor.set(CONFIG, 'availability', 'availability');
					for (let i = 0; i < 2; i++) {
						cursor.set(CONFIG, 'availability', 'target' + (i + 1) + '_url', checked.targets[i].url);
						cursor.set(CONFIG, 'availability', 'target' + (i + 1) + '_status', '' + checked.targets[i].expected_status);
					}
					result = cursor.commit(CONFIG) === true ? get() : { error: 'settings_commit_failed' };
				}
			}
		} catch (e) { result = { error: 'settings_apply_failed' }; }
		lock.close();
		return result;
	}
	return { get: get, apply: apply };
}
export { availabilitySettings };
