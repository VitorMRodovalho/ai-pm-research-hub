import InfoPopover from './InfoPopover';

interface Props {
  i18n: {
    title: string;
    cardTitle: string;
    cardDesc: string;
    checklistTitle: string;
    checklistDesc: string;
    datesTitle: string;
    datesDesc: string;
  };
}

const SECTION = 'mb-3 last:mb-0';
const HEADING = 'text-[12px] font-bold text-[var(--text-primary)] mb-1';
const BODY = 'text-[11px] text-[var(--text-secondary)] whitespace-pre-line leading-[1.6]';

export default function BoardRulesPopover({ i18n }: Props) {
  return (
    <InfoPopover title={i18n.title}>
      <div className={SECTION}>
        <div className={HEADING}>📦 {i18n.cardTitle}</div>
        <div className={BODY}>{i18n.cardDesc}</div>
      </div>
      <div className={SECTION}>
        <div className={HEADING}>☑️ {i18n.checklistTitle}</div>
        <div className={BODY}>{i18n.checklistDesc}</div>
      </div>
      <div className={SECTION}>
        <div className={HEADING}>📊 {i18n.datesTitle}</div>
        <div className={BODY}>{i18n.datesDesc}</div>
      </div>
    </InfoPopover>
  );
}
