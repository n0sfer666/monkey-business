'use strict';
'require baseclass';
'require view.monkey-business.kit.style as style';

style.add('geo', [
	'.mb .mb-geo-sheet .mb-sheet-body{gap:12px;padding:0 18px}',
	'.mb .mb-geo-sheet .mb-sheet-foot{margin-top:14px;padding:14px 18px 16px}',
	'.mb .mb-geo-lead,.mb .mb-geo-up>span,.mb .mb-geo-fd{color:var(--mb-muted)}',
	'.mb .mb-geo-f{display:flex;flex-direction:column;gap:4px}',
	'.mb .mb-geo-f label{font-size:12px;color:var(--mb-muted)}',
	'.mb .mb-sheet-body .mb-input.mb-geo-url{width:100%;font-family:var(--mb-mono)}',
	'.mb .mb-geo-up{display:flex;align-items:center;gap:8px;padding-top:12px;border-top:1px solid var(--mb-line)}',
	'.mb .mb-geo-up>span{flex:1}',
	'.mb .mb-geo-btns{display:contents}',
	'.mb .mb-btn.mb-geo-btn{gap:6px;padding:5px 12px}',
	'.mb .mb-geo-fd{flex:1}',
	'.mb .mb-geo-file{display:none}',
	style.MOBILE + '{',
	'.mb .mb-geo-sheet .mb-sheet-body{padding:14px 16px 0}',
	'.mb .mb-geo-sheet .mb-sheet-foot{margin-top:16px;padding:12px 16px 20px}',
	'.mb .mb-geo-lead,.mb .mb-geo-up>span{font-size:12px}',
	'.mb .mb-sheet-body .mb-input.mb-geo-url{padding:10px 12px;border-radius:6px}',
	'.mb .mb-geo-up{flex-direction:column;align-items:stretch;gap:12px;padding-top:0;border-top:0}',
	'.mb .mb-geo-up .mb-hint-brief{display:block;padding-top:10px;border-top:1px solid var(--mb-line)}',
	'.mb .mb-geo-btns{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}',
	'.mb .mb-btn.mb-geo-btn{justify-content:center;padding:10px 0;border-radius:8px}',
	'.mb .mb-geo-fd{display:none}',
	'}'
].join(''));

return baseclass.extend({});
