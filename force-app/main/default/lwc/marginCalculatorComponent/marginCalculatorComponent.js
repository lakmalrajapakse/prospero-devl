import { LightningElement, api, wire } from 'lwc';
import { getRecord, createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAgreementDetails from '@salesforce/apex/MarginCalculatorController.getAgreementDetails';
import getRateCardPages from '@salesforce/apex/MarginCalculatorController.getRateCardPages';
import getEmployerOnCosts from '@salesforce/apex/MarginCalculatorController.getEmployerOnCosts';
import getAwrRateModifierTypeId from '@salesforce/apex/MarginCalculatorController.getAwrRateModifierTypeId';
import getRateAgreementLineContext from '@salesforce/apex/MarginCalculatorController.getRateAgreementLineContext';
import calculateRateAgreementMargin from '@salesforce/apex/MarginCalculatorController.calculateRateAgreementMargin';
import clonePage from '@salesforce/apex/MarginCalculatorController.clonePage';
import RATE_LINE_OBJECT from '@salesforce/schema/sirenum__Rate_Line__c';
import RATE_LINE_PAGE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Rate_Card_Page__c';
import RATE_LINE_CODE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Code__c';
import RATE_LINE_STANDARD_RATE_TYPE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Standard_Rate_Type__c';
import RATE_LINE_RATE_AGREEMENT_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.Employer_On_Cost__c';
import RATE_LINE_PAY_RATE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Pay_Rate__c';
import RATE_LINE_CHARGE_RATE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Charge_Rate__c';
import RATE_LINE_MARGIN_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.Margin__c';
import RATE_LINE_MARGIN_TYPE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.Margin_Type__c';
import RATE_LINE_UNIT_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Unit__c';
import RATE_LINE_START_HOUR_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Start_Hour__c';
import RATE_LINE_END_HOUR_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__End_Hour__c';
import RATE_LINE_DAY_TYPE_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__Day_Type__c';
import RATE_LINE_SORT_ORDER_FIELD from '@salesforce/schema/sirenum__Rate_Line__c.sirenum__SortOrder__c';
import RATE_CARD_PAGE_NAME_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.Name';
import RATE_CARD_PAGE_VALID_FROM_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Valid_From_Date__c';
import STANDARD_RATE_TYPE_OBJECT from '@salesforce/schema/sirenum__Standard_Rate_Type__c';
import STANDARD_RATE_TYPE_RATE_CODE_FIELD from '@salesforce/schema/sirenum__Standard_Rate_Type__c.sirenum__Rate_Code__c';
import RATE_AGREEMENT_OBJECT from '@salesforce/schema/Rate_Agreements__c';
import RATE_AGREEMENT_TYPE_FIELD from '@salesforce/schema/Rate_Agreements__c.Type__c';
import RATE_MODIFIER_OBJECT from '@salesforce/schema/sirenum__Rate_Modifier__c';
import RATE_MODIFIER_RATE_LINE_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.sirenum__Rate_Line__c';
import RATE_MODIFIER_TYPE_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.sirenum__Rate_Modifier_Type__c';
import RATE_MODIFIER_PAY_RATE_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.sirenum__Pay_Rate__c';
import RATE_MODIFIER_CHARGE_RATE_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.sirenum__Charge_Rate__c';
import RATE_MODIFIER_MARGIN_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.Margin__c';
import RATE_MODIFIER_MARGIN_TYPE_FIELD from '@salesforce/schema/sirenum__Rate_Modifier__c.Margin_Type__c';

// Only Rate Agreements of this Type are relevant here -- same filter employerOnCostManager uses.
const MARGIN_CALCULATOR_TEMPLATE_TYPE = 'Margin Calculator Template';

// sirenum__Unit__c's actual picklist values -- hardcoded rather than an extra getPicklistValues
// wire, since they're stable; revisit if the object's picklist changes.
const UNIT_OPTIONS = [
    { label: 'Hourly', value: 'Hourly' },
    { label: 'Shift', value: 'Shift' },
    { label: 'Daily', value: 'Daily' }
];
// sirenum__Day_Type__c's actual picklist values.
const DAY_TYPE_OPTIONS = [
    { label: 'Any Day', value: 'Any Day' },
    { label: 'Monday', value: 'Monday' },
    { label: 'Tuesday', value: 'Tuesday' },
    { label: 'Wednesday', value: 'Wednesday' },
    { label: 'Thursday', value: 'Thursday' },
    { label: 'Friday', value: 'Friday' },
    { label: 'Saturday', value: 'Saturday' },
    { label: 'Sunday', value: 'Sunday' },
    { label: 'Weekdays', value: 'Weekdays' },
    { label: 'Weekends', value: 'Weekends' }
];
// Margin_Type__c's picklist values.
const MARGIN_TYPE_OPTIONS = [
    { label: 'Fixed', value: 'Fixed' },
    { label: 'Percent', value: 'Percent' }
];
const DEFAULT_UNIT = 'Hourly';
const DEFAULT_DAY_TYPE = 'Any Day';
const DEFAULT_HOUR = '00:00';

export default class MarginCalculatorComponent extends LightningElement {
    // Context passed down from Rate Manager -- see rateManager.html for how each is set per
    // object (Job Role/Placement/Shift).
    @api recordId;
    @api objectName;
    // The Placement whose Job Role/Worker/Contract/Rate Agreement the header shows.
    @api placementId;
    // The Rate Card whose no-condition Page(s) are listed (full "placement" mode) -- a Placement
    // can have more than one over time (each its own effective-dated version).
    @api rateCardId;
    // When set, restricts the view to this one Page only, with no Clone/Edit/Add option -- used
    // for a genuine Shift-condition Page.
    @api rateCardPageId = null;
    // Shift with no Shift-condition Page of its own yet -- shows ONLY the Placement level Page in
    // effect on referenceDate (the Shift's own date), with the usual Placement actions plus a
    // "Create Shift Page" button on each Rate Line. Clicking one fires 'createshiftpage'
    // ({ lineId }) for rateManager to create the Shift-condition Page from.
    @api shiftPageSelectionMode = false;
    // The date deciding which Page counts as "valid" (see resolveValidPageId) -- the Shift's own
    // date for a Shift, today when not given (Placement).
    @api referenceDate;
    // Id of a Rate Card Page rateManager just created (either the Placement auto-create cascade,
    // or "Create Shift Page"). Once that Page's data loads here and it still has zero Rate Lines,
    // the Add Rate Line modal opens for it automatically so a freshly created empty Page never
    // dead-ends. Fires once per component instance (see hasAutoOpenedAddLine below).
    @api autoOpenPageId;
    // Set only alongside autoOpenPageId for a just-created Shift-specific Page -- the Placement
    // Rate Line whose "Create Shift Page" button was clicked, whose field values prefill the
    // auto-opened Add Rate Line modal's form, instead of it opening blank. See
    // applyPrefillLineValuesIfOpen.
    @api prefillLineId;

    rateLineObjectApiName = RATE_LINE_OBJECT.objectApiName;
    standardRateTypeObjectApiName = STANDARD_RATE_TYPE_OBJECT.objectApiName;
    rateAgreementObjectApiName = RATE_AGREEMENT_OBJECT.objectApiName;
    unitOptions = UNIT_OPTIONS;
    dayTypeOptions = DAY_TYPE_OPTIONS;
    marginTypeOptions = MARGIN_TYPE_OPTIONS;

    rateAgreementFilter = {
        criteria: [{ fieldPath: RATE_AGREEMENT_TYPE_FIELD.fieldApiName, operator: 'eq', value: MARGIN_CALCULATOR_TEMPLATE_TYPE }]
    };

    agreementDetails = {};
    pages = [];
    // The Page expanded by default -- see resolveValidPageId. Kept as a plain Id string (as is
    // each Page's own activeLineName) so a refreshApex() with the same result doesn't hand the
    // accordion a new value and collapse whatever else the user has opened since.
    activePageName;
    // Starts true so the spinner shows until the first getRateCardPages result (data or error)
    // arrives -- there's no connectedCallback flip needed since this is the field's own initial
    // value.
    isLoadingPages = true;
    hasAutoOpenedAddLine = false;
    // Set once wiredPages has force-refreshed for a missing autoOpenPageId -- see wiredPages.
    hasRefreshedForAutoOpen = false;
    // wiredPrefillLine's resolved field values -- see applyPrefillLineValuesIfOpen.
    prefillLineFields;

    showAddLineModal = false;
    addLineTargetPageId;
    // Set only when the modal was opened via the per-line Edit button -- handleSaveLine updates
    // this existing record instead of creating a new one when set.
    editingLineId;
    isSavingLine = false;
    // Standard Rate Type is picked via a standalone lightning-record-picker so selecting it can
    // drive Code -- Code is always auto-populated from the chosen Standard Rate Type's own
    // sirenum__Rate_Code__c, never typed in directly.
    selectedStandardRateTypeId;
    derivedCode;
    // Rate Agreement picked via its own standalone lightning-record-picker, filtered to
    // Type = 'Margin Calculator Template'. Injected into Employer_On_Cost__c (a lookup to
    // Rate_Agreements__c, despite the field's name) on submit.
    selectedRateAgreementId;
    showEmployerOnCostModal = false;
    // Employer On Cost rows applicable to this Placement's Worker Type, for whichever Rate
    // Agreement is selected above -- drives the live Pay/Charge/Margin calculation below.
    employerOnCosts = [];
    // Plain fields on the custom Add Rate Line form -- built without lightning-record-edit-form
    // so Unit/Start Hour/End Hour/Day Type/Margin Type can be added and Day Type can be hidden
    // in restricted (Shift-specific) mode. Pay Rate/Charge Rate/Margin Type/Margin are grouped
    // together at the end of the form since they react to each other.
    lineUnit = DEFAULT_UNIT;
    lineStartHour = DEFAULT_HOUR;
    lineEndHour = DEFAULT_HOUR;
    lineDayType = DEFAULT_DAY_TYPE;
    linePayRate;
    lineChargeRate;
    lineMarginType;
    lineMargin;
    // Which of Margin/Charge Rate the user last typed into directly -- the live calculation
    // always recomputes the OTHER one from this, so it never fights the field the user is
    // actively editing. Reset whenever the modal (re)opens.
    lastEditedRateField;

    // AWR (Agency Workers Regulations) -- an optional sirenum__Rate_Modifier__c child of this
    // Rate Line, linked to the single sirenum__Rate_Modifier_Type__c record named 'AWR'. Reuses
    // this same modal's employerOnCosts (loaded for the parent Rate Line's own Employer On Cost)
    // for its own Total Cost calculation rather than fetching a separate breakdown.
    awrApplies = false;
    // Set when editing a Rate Line that already has an AWR modifier -- handleSaveLine updates it
    // in place; if awrApplies is unticked and saved, this existing record is deleted instead.
    existingAwrModifierId;
    awrPayRate;
    awrChargeRate;
    awrMarginType;
    awrMargin;
    awrLastEditedRateField;
    // The 'AWR' sirenum__Rate_Modifier_Type__c record's Id -- looked up once, never user-picked.
    awrRateModifierTypeId;

    // Rate Agreement mode (the Placement's Contract has its own Rate Agreement -- see
    // isRateAgreementMode) -- the resolved Rate Agreement Line context (calc type/margin
    // rule/pay scale/employer on costs) for whichever Page the modal is open against. Set only
    // when opening the modal in this mode (see rateAgreementContextPageId), so the wire below
    // never fires (and never overwrites employerOnCosts) in Employer On Cost mode.
    rateAgreementContextPageId;
    rateAgreementLineContext;
    showViewEmployerOnCostModal = false;
    // Disables the Calculate/Recalculate buttons and Save while a calculateRateAgreementMargin
    // round-trip is in flight.
    isCalculatingLine = false;
    // setTimeout handles for scheduleRateAgreementRecalc's debounce -- one per field group (main
    // line vs AWR) so editing both in quick succession doesn't cancel each other's pending call.
    lineRecalcTimer;
    awrRecalcTimer;
    // Inline calculation/validation errors -- shown as a block above the Pay/Charge Rate group
    // (and inside the AWR box) instead of toasts. Each pipeline run sets its own on failure and
    // clears it on success (see setCalcError), so a fixed error disappears on the next run.
    lineCalcError;
    awrCalcError;
    // Employer On Cost mode only -- set once Recalculate is clicked with a prerequisite missing;
    // the message itself is derived live (see eocRecalcPrereqError).
    eocRecalcAttempted = false;
    // A failed save's DML error -- cleared on the next save attempt or when the modal reopens.
    saveLineError;

    // "Clone" Page -- prompts for a name and an Effective Date, then copies every Rate Line (and
    // AWR modifier) from clonePageSourceId onto a brand new Page on the same Rate Card, and ends
    // the source Page the day before that Effective Date (see Apex clonePage()).
    showClonePageModal = false;
    clonePageSourceId;
    clonePageName = '';
    clonePageEffectiveDate;
    isCloningPage = false;

    // "Edit" Page -- Name and Valid From are editable; Valid Until is shown read-only (it's only
    // ever set by Clone, ending a Page the day before its successor starts).
    showEditPageModal = false;
    editPageId;
    editPageName;
    editPageValidFromDate;
    editPageValidUntilDate;
    isSavingPageEdit = false;

    // Kept so refreshApex() can bypass this cacheable method's cache after adding a Rate Line.
    wiredPagesResult;
    // Kept so refreshApex() can bypass getEmployerOnCosts' cache -- see handleRefreshEmployerOnCost.
    wiredEmployerOnCostsResult;

    @wire(getAgreementDetails, { placementId: '$placementId' })
    wiredAgreementDetails({ data, error }) {
        if (data) {
            this.agreementDetails = data;
        } else if (error) {
            this.showError(error);
        }
    }

    @wire(getRateCardPages, { rateCardId: '$rateCardId', onlyPageId: '$rateCardPageId' })
    wiredPages(result) {
        this.wiredPagesResult = result;
        const { data, error } = result;
        if (data) {
            // getRateCardPages is cacheable, so a result cached before autoOpenPageId was created
            // (e.g. an earlier empty view of this same Rate Card) can come back without it. Refetch
            // once, bypassing the cache, so the new Page shows and auto-opens without a manual page
            // refresh. isLoadingPages stays true meanwhile.
            if (this.autoOpenPageId && !this.hasRefreshedForAutoOpen && !data.some((p) => p.page.Id === this.autoOpenPageId)) {
                this.hasRefreshedForAutoOpen = true;
                refreshApex(this.wiredPagesResult).catch((refreshError) => this.showError(refreshError));
                return;
            }
            const pages = data.map((pageWithLines) => {
                // Apex now returns each entry as a LineWithAwr wrapper ({ line, awrModifier }) --
                // awrModifier is null when this Rate Line has no AWR modifier.
                const lines = pageWithLines.lines.map((entry) => ({
                    line: entry.line,
                    awrModifier: entry.awrModifier,
                    key: entry.line.Id,
                    summaryLabel: this.buildLineSummary(entry.line, entry.awrModifier)
                }));
                return {
                    ...pageWithLines,
                    key: pageWithLines.page.Id,
                    validFromLabel: this.buildPageLabel(pageWithLines.page),
                    lines,
                    // Lines come back sorted by Sort Order, so the last one is the latest added.
                    activeLineName: lines.length ? lines[lines.length - 1].key : undefined
                };
            });
            this.activePageName = this.resolveValidPageId(pages);
            this.pages = this.shiftPageSelectionMode
                ? pages.filter((p) => p.key === this.activePageName)
                : pages;
            this.isLoadingPages = false;
            this.maybeAutoOpenAddLine();
        } else if (error) {
            this.pages = [];
            this.isLoadingPages = false;
            this.showError(error);
        }
    }

    // Looked up once -- the AWR toggle links every AWR Rate Modifier it creates to this same
    // sirenum__Rate_Modifier_Type__c record, so the user never picks one.
    @wire(getAwrRateModifierTypeId)
    wiredAwrRateModifierTypeId({ data, error }) {
        if (data) {
            this.awrRateModifierTypeId = data;
        } else if (error) {
            this.awrRateModifierTypeId = undefined;
        }
    }

    // Resolves the applicable Rate Agreement Line (and its own Employer On Cost breakdown) for
    // the target Page -- only fires when rateAgreementContextPageId is set (Rate Agreement mode
    // only, see its own doc comment). Populates the SAME employerOnCosts array Employer On Cost
    // mode's own wire populates, so getTotalEmployerOnCostValue/getTotalCostFor (and AWR, which
    // reuses them) work identically in both modes without change.
    @wire(getRateAgreementLineContext, { placementId: '$placementId', rateCardPageId: '$rateAgreementContextPageId' })
    wiredRateAgreementLineContext({ data, error }) {
        if (data) {
            this.rateAgreementLineContext = data;
            this.employerOnCosts = data.errorMessage
                ? []
                : (data.employerOnCosts || []).filter((cost) => !cost.Worker_Type__c || cost.Worker_Type__c === data.workerType);
            this.applyRateAgreementDefaults();
            this.autoCalculateRateAgreementLine();
        } else if (error) {
            this.rateAgreementLineContext = undefined;
            this.employerOnCosts = [];
        }
    }

    // The Placement Rate Line whose "Create Shift Page" was clicked, to prefill a just-auto-opened
    // Shift-specific Rate Line's form from -- AWR is deliberately never part of this (it doesn't
    // apply to Shift-specific Lines at all, see showAwrSection). Only fires once prefillLineId is
    // set, i.e. only for a just-created Shift-specific Page's auto-open (see the @api doc comment).
    @wire(getRecord, {
        recordId: '$prefillLineId',
        fields: [
            RATE_LINE_STANDARD_RATE_TYPE_FIELD,
            RATE_LINE_RATE_AGREEMENT_FIELD,
            RATE_LINE_UNIT_FIELD,
            RATE_LINE_START_HOUR_FIELD,
            RATE_LINE_END_HOUR_FIELD,
            RATE_LINE_PAY_RATE_FIELD,
            RATE_LINE_CHARGE_RATE_FIELD,
            RATE_LINE_MARGIN_FIELD,
            RATE_LINE_MARGIN_TYPE_FIELD
        ]
    })
    wiredPrefillLine({ data, error }) {
        if (data) {
            this.prefillLineFields = data.fields;
            this.applyPrefillLineValuesIfOpen();
        } else if (error) {
            this.prefillLineFields = undefined;
        }
    }

    // Applies prefillLineFields onto the currently-open (new, not editing) Add Rate Line modal's
    // form -- called both right after auto-opening it (maybeAutoOpenAddLine) and whenever
    // wiredPrefillLine itself resolves, since either can arrive first (the modal may already be
    // open and blank when the prefill data lands, or vice versa). A no-op once either condition
    // isn't met, so it's safe to call speculatively from both places.
    applyPrefillLineValuesIfOpen() {
        if (!this.showAddLineModal || this.editingLineId || !this.prefillLineFields) {
            return;
        }
        // Guards against prefilling some OTHER Add Rate Line modal the user opens manually
        // afterward -- this only ever targets the specific Page that was auto-opened.
        if (this.autoOpenPageId && this.addLineTargetPageId !== this.autoOpenPageId) {
            return;
        }
        const f = this.prefillLineFields;
        this.selectedStandardRateTypeId = f.sirenum__Standard_Rate_Type__c.value;
        this.selectedRateAgreementId = f.Employer_On_Cost__c.value;
        this.lineUnit = f.sirenum__Unit__c.value || DEFAULT_UNIT;
        this.lineStartHour = f.sirenum__Start_Hour__c.value || DEFAULT_HOUR;
        this.lineEndHour = f.sirenum__End_Hour__c.value || DEFAULT_HOUR;
        this.linePayRate = f.sirenum__Pay_Rate__c.value;
        this.lineChargeRate = f.sirenum__Charge_Rate__c.value;
        this.lineMarginType = f.Margin_Type__c.value || 'Percent';
        this.lineMargin = f.Margin__c.value;
    }

    // Selecting a Standard Rate Type in the Add Rate Line modal drives Code -- always read from
    // that record's own sirenum__Rate_Code__c, never typed in directly.
    @wire(getRecord, { recordId: '$selectedStandardRateTypeId', fields: [STANDARD_RATE_TYPE_RATE_CODE_FIELD] })
    wiredStandardRateType({ data, error }) {
        if (data) {
            this.derivedCode = data.fields.sirenum__Rate_Code__c.value;
        } else if (error) {
            this.derivedCode = undefined;
        }
    }

    // Selecting an Employer On Cost (Rate Agreement) in the Add Rate Line modal loads its
    // Worker-Type-applicable cost rows, which then drive the live Pay/Charge/Margin calculation.
    // Kept so refreshApex() can bypass this cacheable method's cache -- see
    // handleRefreshEmployerOnCost below.
    @wire(getEmployerOnCosts, { rateAgreementId: '$selectedRateAgreementId', placementId: '$placementId' })
    wiredEmployerOnCosts(result) {
        this.wiredEmployerOnCostsResult = result;
        const { data, error } = result;
        if (data) {
            this.employerOnCosts = data;
            this.recalculate();
            this.recalculateAwr();
        } else if (error) {
            this.employerOnCosts = [];
        }
    }

    // The Page in effect on referenceDate (today when not given) -- same precedence as Apex
    // RateManagerController.getPrefillRateLineId: a Page whose [Valid From, Valid Until] window
    // brackets the date, else an open-ended one already started by then (latest Valid From wins
    // either way). Falls back to the latest Page overall when none is in effect. Dates are ISO
    // 'YYYY-MM-DD' strings, so plain string comparison orders them correctly.
    resolveValidPageId(pages) {
        if (!pages.length) {
            return undefined;
        }
        const refDate = this.referenceDate || this.todayIso();
        let bracketing;
        let openEnded;
        pages.forEach(({ page }) => {
            const from = page.sirenum__Valid_From_Date__c;
            const until = page.sirenum__Valid_Until_Date__c;
            if (!from || from > refDate) {
                return;
            }
            if (until) {
                if (until >= refDate && (!bracketing || from > bracketing.sirenum__Valid_From_Date__c)) {
                    bracketing = page;
                }
            } else if (!openEnded || from > openEnded.sirenum__Valid_From_Date__c) {
                openEnded = page;
            }
        });
        if (bracketing || openEnded) {
            return (bracketing || openEnded).Id;
        }
        // Latest Valid From; >= so a later Sort Order wins a tie (pages come back in Sort Order).
        return pages.reduce((latest, p) =>
            (p.page.sirenum__Valid_From_Date__c || '') >= (latest.page.sirenum__Valid_From_Date__c || '') ? p : latest
        ).page.Id;
    }

    todayIso() {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }

    // Shift page selection mode only -- rateManager creates the Shift-condition Page and reopens
    // this component in restricted mode on it, with this Line as the prefill source.
    handleCreateShiftPage(event) {
        this.dispatchEvent(new CustomEvent('createshiftpage', {
            detail: { lineId: event.currentTarget.dataset.lineId }
        }));
    }

    buildPageLabel(page) {
        const dateLabel = page.sirenum__Valid_From_Date__c
            ? `Valid from ${page.sirenum__Valid_From_Date__c}`
            : 'Valid from date not set';
        return page.Name ? `${dateLabel} - ${page.Name}` : dateLabel;
    }

    buildLineSummary(line, awrModifier) {
        const parts = [];
        if (line.sirenum__Code__c) parts.push(line.sirenum__Code__c);
        if (line.sirenum__Pay_Rate__c !== null && line.sirenum__Pay_Rate__c !== undefined) parts.push(`Pay £${line.sirenum__Pay_Rate__c}`);
        if (line.sirenum__Charge_Rate__c !== null && line.sirenum__Charge_Rate__c !== undefined) parts.push(`Charge £${line.sirenum__Charge_Rate__c}`);
        if (line.Margin__c !== null && line.Margin__c !== undefined) parts.push(`Margin ${line.Margin__c}%`);
        if (awrModifier) parts.push('AWR');
        return parts.length ? parts.join('  ·  ') : (line.Name || 'Rate Line');
    }

    // Only fires for the specific Page rateManager tells us it just created, and only while that
    // Page still has zero Rate Lines -- see the autoOpenPageId doc comment above.
    maybeAutoOpenAddLine() {
        if (!this.autoOpenPageId || this.hasAutoOpenedAddLine || !this.canAddRateLine) {
            return;
        }
        const target = this.pages.find((p) => p.page.Id === this.autoOpenPageId);
        if (target && target.lines.length === 0) {
            this.hasAutoOpenedAddLine = true;
            this.openAddLineModalForPage(target.page.Id);
            this.applyPrefillLineValuesIfOpen();
        }
    }

    // Restricted mode is driven purely by whether the parent handed us a specific Page to lock
    // onto -- see the rateCardPageId doc comment above.
    get isRestrictedMode() {
        return !!this.rateCardPageId;
    }

    // Clone/Edit/Add are all unavailable for a genuine Shift-condition Page -- view and (once
    // built) edit existing Rate Lines only.
    // Placement Pages keep Clone/Edit/Add wherever they're shown (including from a Shift in
    // shiftPageSelectionMode) -- only a genuine Shift-condition Page is restricted.
    get showFullPageActions() {
        return !this.isRestrictedMode;
    }

    get noPagesMessage() {
        return this.shiftPageSelectionMode
            ? "No Rate Card Page found on this Shift's Placement. Set one up on the Placement first."
            : 'No Rate Card Pages found.';
    }

    get noLinesMessage() {
        return this.shiftPageSelectionMode
            ? 'No Rate Lines on this Page yet. Add one to base a Shift Page on.'
            : 'No Rate Lines on this Page yet.';
    }

    // Day Type doesn't apply to a Shift-specific Page (it's already pinned to one exact day).
    get showDayType() {
        return !this.isRestrictedMode;
    }

    get showAgreementDetails() {
        return !!this.placementId;
    }

    // The Placement's Contract has its own Rate Agreement -- margin then follows that Rate
    // Agreement's own trigger-based rules (Rate_Agreement_Lines__c etc, see
    // rateLineTriggerCustomHandler) via getRateAgreementLineContext/calculateRateAgreementMargin
    // below, instead of a user-picked Employer On Cost. Set server-side by getAgreementDetails,
    // already blocked from ever reaching this component at all when the Placement can't be
    // validated against it (see agreementBlockingError).
    get isRateAgreementMode() {
        return !!this.agreementDetails?.hasRateAgreement;
    }

    get showEmployerOnCost() {
        return !this.isRateAgreementMode;
    }

    // Set (only when isRateAgreementMode) when the Placement can't actually be validated against
    // its Contract's Rate Agreement -- blocks Add Rate Line entirely (see canAddRateLine) and is
    // shown as an on-screen error instead, same as rateManager blocks Rate Card/Page creation on
    // it.
    get agreementBlockingError() {
        return this.agreementDetails?.blockingError;
    }

    get canAddRateLine() {
        return !this.agreementBlockingError;
    }

    // Blocked entirely -- not just "no Add Rate Line" but no Rate Card Page/Rate Line listing at
    // all, since none of it can be trusted (or added to) until the Placement can actually be
    // validated against its Contract's Rate Agreement. Only the blocking banner above shows.
    get showRateCardPages() {
        return !this.agreementBlockingError;
    }

    isFixedCalcType(calcType) {
        return calcType === 'Fixed Margin Amount' || calcType === 'Fixed Margin %';
    }

    isPercentCalcType(calcType) {
        return calcType === 'Fixed Margin %' || calcType === 'Max Margin %';
    }

    // Bound in the template -- true only once a Rate Agreement Line has actually resolved AND
    // it's a Fixed (not Max) calc type, so Margin is locked/disabled. False (never disabled) in
    // Employer On Cost mode.
    get isCurrentCalcTypeFixed() {
        return this.isRateAgreementMode && this.isFixedCalcType(this.rateAgreementLineContext?.calcType);
    }

    // Percent-type rows are a percentage of Pay Rate, so they can't be pre-summed server-side --
    // Pay Rate is live client-side input. Fixed-type rows are added as-is. Parameterized so the
    // AWR section below can reuse the SAME employerOnCosts breakdown against its own Pay Rate,
    // instead of fetching a separate one.
    getTotalEmployerOnCostValue(payRateInput) {
        const payRate = parseFloat(payRateInput) || 0;
        return this.employerOnCosts.reduce((sum, cost) => {
            if (cost.Value__c === null || cost.Value__c === undefined) {
                return sum;
            }
            const amount = cost.Calc_Type__c === 'Percent' ? (cost.Value__c / 100) * payRate : cost.Value__c;
            return sum + amount;
        }, 0);
    }

    getTotalCostFor(payRateInput) {
        const payRate = parseFloat(payRateInput) || 0;
        return payRate + this.getTotalEmployerOnCostValue(payRateInput);
    }

    get totalEmployerOnCostValue() {
        return this.getTotalEmployerOnCostValue(this.linePayRate);
    }

    get totalCost() {
        return this.getTotalCostFor(this.linePayRate);
    }

    get showTotalCost() {
        if (this.showEmployerOnCost) {
            return !!this.selectedRateAgreementId;
        }
        return !!this.rateAgreementLineContext?.rateAgreementLineId;
    }

    get totalCostDisplay() {
        return this.totalCost.toFixed(2);
    }

    // AWR box is offered whenever there's an Employer On Cost breakdown to calculate against --
    // either a user-picked Employer On Cost (see showEmployerOnCost) or a resolved Rate Agreement
    // Line (Rate Agreement mode) -- since its own calculation reuses that same employerOnCosts
    // breakdown either way.
    get showAwrSection() {
        // AWR doesn't apply to a genuine Shift-condition Page at all.
        if (this.isRestrictedMode) {
            return false;
        }
        if (this.showEmployerOnCost) {
            return true;
        }
        return !!this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage;
    }

    get awrTotalCost() {
        return this.getTotalCostFor(this.awrPayRate);
    }

    get awrTotalCostDisplay() {
        return this.awrTotalCost.toFixed(2);
    }

    get showAwrTotalCost() {
        if (!this.awrApplies) {
            return false;
        }
        if (this.showEmployerOnCost) {
            return !!this.selectedRateAgreementId;
        }
        return !!this.rateAgreementLineContext?.rateAgreementLineId;
    }

    get hasNoPages() {
        return !this.isLoadingPages && this.pages.length === 0;
    }

    get modalTitle() {
        return this.editingLineId ? 'Edit Rate Line' : 'Add Rate Line';
    }

    // Called once the Rate Agreement Line context resolves (or re-resolves). Pay Rate defaults to
    // the Scale's own Min Amount (only when it isn't already set -- editing an existing Rate Line
    // keeps its own saved Pay Rate) so a Charge/Margin can be computed immediately, without
    // waiting on the user to type one in first -- see autoCalculateRateAgreementLine. Margin Type
    // is always auto-derived from the Line's own Calc_Type__c (never user-picked, in either mode
    // -- see the read-only Margin Type display in the template). For a Fixed calc type, Margin is
    // always forced to the Line's own Margin_Value__c (locked/disabled in the template). For a
    // Max calc type, Margin only defaults to Margin_Value__c (the cap) when it isn't already set.
    applyRateAgreementLineDefaults() {
        const ctx = this.rateAgreementLineContext;
        if (!ctx || ctx.errorMessage) {
            return;
        }
        if (this.linePayRate === undefined || this.linePayRate === null || this.linePayRate === '') {
            this.linePayRate = ctx.payScaleMin;
        }
        this.lineMarginType = this.isPercentCalcType(ctx.calcType) ? 'Percent' : 'Fixed';
        if (this.isFixedCalcType(ctx.calcType)) {
            this.lineMargin = ctx.marginValue;
        } else if (this.lineMargin === undefined || this.lineMargin === null || this.lineMargin === '') {
            this.lineMargin = ctx.marginValue;
        }
    }

    applyRateAgreementAwrDefaults() {
        const ctx = this.rateAgreementLineContext;
        if (!ctx || ctx.errorMessage) {
            return;
        }
        if (this.awrPayRate === undefined || this.awrPayRate === null || this.awrPayRate === '') {
            this.awrPayRate = ctx.payScaleMin;
        }
        this.awrMarginType = this.isPercentCalcType(ctx.calcType) ? 'Percent' : 'Fixed';
        if (this.isFixedCalcType(ctx.calcType)) {
            this.awrMargin = ctx.marginValue;
        } else if (this.awrMargin === undefined || this.awrMargin === null || this.awrMargin === '') {
            this.awrMargin = ctx.marginValue;
        }
    }

    applyRateAgreementDefaults() {
        this.applyRateAgreementLineDefaults();
        if (this.awrApplies) {
            this.applyRateAgreementAwrDefaults();
        }
    }

    // Runs the same Calculate pipeline automatically once the Rate Agreement Line context (and
    // its defaulted Pay Rate) is ready, so Charge Rate/Margin are already populated by the time
    // the user sees the modal -- no button needed to kick off the first calculation. Errors (e.g.
    // a defaulted Pay Rate that somehow still fails, which shouldn't normally happen) surface via
    // the same toast calculateAndValidateRateAgreementLine already raises; deliberately no success
    // toast here (that's reserved for an explicit Recalculate click) -- fire-and-forget.
    autoCalculateRateAgreementLine() {
        const ctx = this.rateAgreementLineContext;
        if (!ctx || ctx.errorMessage) {
            return;
        }
        this.calculateAndValidateRateAgreementLine(false).then((lineOk) => {
            if (lineOk && this.awrApplies) {
                this.calculateAndValidateRateAgreementLine(true);
            }
        });
    }

    // Pay Rate's allowed range under the resolved Rate Agreement Scale -- shown above the Pay
    // Rate field (main and AWR) so the user knows the bounds before typing, even though Pay Rate
    // now defaults to the Min Amount and the range is still enforced on Calculate/Save regardless.
    get payScaleRangeDisplay() {
        const ctx = this.rateAgreementLineContext;
        if (!ctx) {
            return '';
        }
        const min = ctx.payScaleMin !== null && ctx.payScaleMin !== undefined ? `£${Number(ctx.payScaleMin).toFixed(2)}` : 'no minimum';
        const max = ctx.payScaleMax !== null && ctx.payScaleMax !== undefined ? `£${Number(ctx.payScaleMax).toFixed(2)}` : 'no maximum';
        return `Allowed range: ${min} - ${max}`;
    }

    openAddLineModal(event) {
        this.openAddLineModalForPage(event.currentTarget.dataset.pageId);
    }

    openAddLineModalForPage(pageId) {
        this.addLineTargetPageId = pageId;
        this.editingLineId = undefined;
        this.resetLineForm();
        if (this.isRateAgreementMode) {
            this.rateAgreementContextPageId = pageId;
        }
        this.showAddLineModal = true;
    }

    // Opens the same modal pre-filled from an existing Rate Line -- handleSaveLine updates it in
    // place instead of creating a new one. Standard Rate Type/Employer On Cost are set by Id;
    // their own reactive wires (keyed on those Ids) re-fetch Code and the cost breakdown, same as
    // a fresh selection would.
    // awrModifier is the existing sirenum__Rate_Modifier__c child (or undefined) -- when present,
    // the AWR toggle starts ON and its fields prefill from it.
    openEditLineModal(pageId, line, awrModifier) {
        this.addLineTargetPageId = pageId;
        this.editingLineId = line.Id;
        this.resetLineForm();
        this.selectedStandardRateTypeId = line.sirenum__Standard_Rate_Type__c;
        this.selectedRateAgreementId = line.Employer_On_Cost__c;
        this.lineUnit = line.sirenum__Unit__c || DEFAULT_UNIT;
        this.lineStartHour = line.sirenum__Start_Hour__c || DEFAULT_HOUR;
        this.lineEndHour = line.sirenum__End_Hour__c || DEFAULT_HOUR;
        this.lineDayType = line.sirenum__Day_Type__c || DEFAULT_DAY_TYPE;
        this.linePayRate = line.sirenum__Pay_Rate__c;
        this.lineChargeRate = line.sirenum__Charge_Rate__c;
        this.lineMarginType = line.Margin_Type__c || 'Percent';
        this.lineMargin = line.Margin__c;
        if (awrModifier) {
            this.awrApplies = true;
            this.existingAwrModifierId = awrModifier.Id;
            this.awrPayRate = awrModifier.sirenum__Pay_Rate__c;
            this.awrChargeRate = awrModifier.sirenum__Charge_Rate__c;
            this.awrMarginType = awrModifier.Margin_Type__c || 'Percent';
            this.awrMargin = awrModifier.Margin__c;
        }
        if (this.isRateAgreementMode) {
            this.rateAgreementContextPageId = pageId;
        }
        this.showAddLineModal = true;
    }

    resetLineForm() {
        this.selectedStandardRateTypeId = undefined;
        this.derivedCode = undefined;
        this.selectedRateAgreementId = undefined;
        this.employerOnCosts = [];
        this.lineUnit = DEFAULT_UNIT;
        this.lineStartHour = DEFAULT_HOUR;
        this.lineEndHour = DEFAULT_HOUR;
        this.lineDayType = DEFAULT_DAY_TYPE;
        this.linePayRate = undefined;
        this.lineChargeRate = undefined;
        this.lineMarginType = 'Percent';
        this.lineMargin = undefined;
        this.lastEditedRateField = undefined;
        this.awrApplies = false;
        this.existingAwrModifierId = undefined;
        this.awrPayRate = undefined;
        this.awrChargeRate = undefined;
        this.awrMarginType = 'Percent';
        this.awrMargin = undefined;
        this.awrLastEditedRateField = undefined;
        this.rateAgreementContextPageId = undefined;
        this.rateAgreementLineContext = undefined;
        this.showViewEmployerOnCostModal = false;
        this.lineCalcError = undefined;
        this.awrCalcError = undefined;
        this.eocRecalcAttempted = false;
        this.saveLineError = undefined;
        clearTimeout(this.lineRecalcTimer);
        clearTimeout(this.awrRecalcTimer);
    }

    closeAddLineModal() {
        this.showAddLineModal = false;
        this.addLineTargetPageId = undefined;
        this.editingLineId = undefined;
    }

    // Looks up the target Page and Line from their Ids (data-page-id/data-line-id on the button)
    // and opens the modal pre-filled from it.
    handleEditLine(event) {
        const pageId = event.currentTarget.dataset.pageId;
        const lineId = event.currentTarget.dataset.lineId;
        const page = this.pages.find((p) => p.page.Id === pageId);
        const entry = page?.lines.find((l) => l.line.Id === lineId);
        if (entry) {
            this.openEditLineModal(pageId, entry.line, entry.awrModifier);
        }
    }

    handleStandardRateTypeChange(event) {
        this.selectedStandardRateTypeId = event.detail.recordId;
        if (!this.selectedStandardRateTypeId) {
            this.derivedCode = undefined;
        }
    }

    handleRateAgreementChange(event) {
        this.selectedRateAgreementId = event.detail.recordId;
        if (!this.selectedRateAgreementId) {
            this.employerOnCosts = [];
            this.recalculate();
        }
        // A new selection re-fires wiredEmployerOnCosts above, which calls recalculate() itself
        // once the new cost rows arrive.
    }

    // Re-fetches this Employer On Cost's cost rows and worker-type resolution from scratch
    // (bypassing the cache) and recalculates Total Cost/Charge Rate against them -- called when
    // the Employer On Cost modal closes, in case anything was created/edited in there.
    async handleRefreshEmployerOnCost() {
        if (!this.selectedRateAgreementId || !this.wiredEmployerOnCostsResult) {
            return;
        }
        try {
            await refreshApex(this.wiredEmployerOnCostsResult);
            this.recalculate();
            this.recalculateAwr();
        } catch (error) {
            this.showError(error);
        }
    }

    handlePayRateChange(event) {
        this.linePayRate = event.target.value;
        this.recalculate();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            // Pay Rate changing invalidates any Charge Rate the user typed directly -- Charge is
            // always the derived quantity from here (forward from Margin), same as a fresh
            // Calculate would do; a Fixed calc type's Margin never moves regardless (see
            // calculateAndValidateRateAgreementLine).
            this.lastEditedRateField = 'margin';
            this.scheduleRateAgreementRecalc(false);
        }
    }

    handleChargeRateChange(event) {
        this.lineChargeRate = event.target.value;
        this.lastEditedRateField = 'charge';
        this.recalculateMarginFromCharge();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            // Only a Max calc type's Margin actually moves here (see
            // calculateAndValidateRateAgreementLine) -- a Fixed one's Charge Rate just gets
            // snapped back to what Pay Rate + the fixed Margin requires.
            this.scheduleRateAgreementRecalc(false);
        }
    }

    // Changing Margin Type always recomputes Charge Rate fresh from the existing Margin value --
    // converting the old Margin number across Fixed/Percent wouldn't be meaningful.
    handleMarginTypeChange(event) {
        this.lineMarginType = event.detail.value;
        this.recalculateChargeFromMargin();
    }

    handleMarginChange(event) {
        this.lineMargin = event.target.value;
        this.lastEditedRateField = 'margin';
        this.recalculateChargeFromMargin();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            // Only reachable for a Max calc type anyway -- Margin is disabled in the template for
            // a Fixed one, so this never fires there.
            this.scheduleRateAgreementRecalc(false);
        }
    }

    // Only meaningful once an Employer On Cost is selected (Non-Rate-Agreement lines only --
    // see showEmployerOnCost) and a Margin Type is chosen. Recomputes whichever of
    // Margin/Charge Rate the user isn't actively typing into, from the other -- see
    // lastEditedRateField.
    recalculate() {
        if (!this.showEmployerOnCost || !this.selectedRateAgreementId) {
            return;
        }
        if (this.lastEditedRateField === 'charge') {
            this.recalculateMarginFromCharge();
        } else {
            this.recalculateChargeFromMargin();
        }
    }

    recalculateChargeFromMargin() {
        if (!this.showEmployerOnCost || !this.selectedRateAgreementId || !this.lineMarginType) {
            return;
        }
        const margin = parseFloat(this.lineMargin);
        if (Number.isNaN(margin)) {
            return;
        }
        const totalCost = this.totalCost;
        this.lineChargeRate = this.lineMarginType === 'Percent'
            ? (totalCost * (1 + margin / 100)).toFixed(2)
            : (totalCost + margin).toFixed(2);
    }

    recalculateMarginFromCharge() {
        if (!this.showEmployerOnCost || !this.selectedRateAgreementId || !this.lineMarginType) {
            return;
        }
        const charge = parseFloat(this.lineChargeRate);
        if (Number.isNaN(charge)) {
            return;
        }
        const totalCost = this.totalCost;
        this.lineMargin = this.lineMarginType === 'Percent'
            ? (totalCost ? (((charge - totalCost) / totalCost) * 100).toFixed(2) : '0.00')
            : (charge - totalCost).toFixed(2);
    }

    handleAwrAppliesChange(event) {
        this.awrApplies = event.target.checked;
        if (this.awrApplies && this.isRateAgreementMode) {
            this.applyRateAgreementAwrDefaults();
            this.calculateAndValidateRateAgreementLine(true);
        }
    }

    handleAwrPayRateChange(event) {
        this.awrPayRate = event.target.value;
        this.recalculateAwr();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            this.awrLastEditedRateField = 'margin';
            this.scheduleRateAgreementRecalc(true);
        }
    }

    handleAwrChargeRateChange(event) {
        this.awrChargeRate = event.target.value;
        this.awrLastEditedRateField = 'charge';
        this.recalculateAwrMarginFromCharge();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            this.scheduleRateAgreementRecalc(true);
        }
    }

    // lightning-input fires its change event on every keystroke, not just on blur -- without
    // debouncing, typing over "48.00" with "49.00" would momentarily validate "4" (or "49") against
    // the Pay Scale/margin rule and show a spurious error before the user finishes typing. Only the
    // last edit within this window actually triggers a recalculation; every earlier one is
    // cancelled. isAwr gets its own timer so editing the main line and the AWR modifier in the same
    // window don't cancel each other.
    scheduleRateAgreementRecalc(isAwr) {
        const timerKey = isAwr ? 'awrRecalcTimer' : 'lineRecalcTimer';
        clearTimeout(this[timerKey]);
        this[timerKey] = setTimeout(() => {
            this.calculateAndValidateRateAgreementLine(isAwr);
        }, 600);
    }

    handleAwrMarginTypeChange(event) {
        this.awrMarginType = event.detail.value;
        this.recalculateAwrChargeFromMargin();
    }

    handleAwrMarginChange(event) {
        this.awrMargin = event.target.value;
        this.awrLastEditedRateField = 'margin';
        this.recalculateAwrChargeFromMargin();
        if (this.isRateAgreementMode && this.rateAgreementLineContext && !this.rateAgreementLineContext.errorMessage) {
            this.scheduleRateAgreementRecalc(true);
        }
    }

    // Same shape as recalculate()/recalculateChargeFromMargin()/recalculateMarginFromCharge()
    // above, but against the AWR fields and awrTotalCost (which reuses this modal's
    // employerOnCosts breakdown against the AWR's own Pay Rate -- see getTotalCostFor).
    recalculateAwr() {
        if (!this.awrApplies || !this.selectedRateAgreementId || !this.awrMarginType) {
            return;
        }
        if (this.awrLastEditedRateField === 'charge') {
            this.recalculateAwrMarginFromCharge();
        } else {
            this.recalculateAwrChargeFromMargin();
        }
    }

    recalculateAwrChargeFromMargin() {
        if (!this.awrApplies || !this.selectedRateAgreementId || !this.awrMarginType) {
            return;
        }
        const margin = parseFloat(this.awrMargin);
        if (Number.isNaN(margin)) {
            return;
        }
        const totalCost = this.awrTotalCost;
        this.awrChargeRate = this.awrMarginType === 'Percent'
            ? (totalCost * (1 + margin / 100)).toFixed(2)
            : (totalCost + margin).toFixed(2);
    }

    recalculateAwrMarginFromCharge() {
        if (!this.awrApplies || !this.selectedRateAgreementId || !this.awrMarginType) {
            return;
        }
        const charge = parseFloat(this.awrChargeRate);
        if (Number.isNaN(charge)) {
            return;
        }
        const totalCost = this.awrTotalCost;
        this.awrMargin = this.awrMarginType === 'Percent'
            ? (totalCost ? (((charge - totalCost) / totalCost) * 100).toFixed(2) : '0.00')
            : (charge - totalCost).toFixed(2);
    }

    // Rate Agreement mode's Pay Rate -> Margin/Charge pipeline, for either the main Rate Line
    // (isAwr false) or its AWR modifier (isAwr true) -- both are governed by the SAME resolved
    // Rate Agreement Line, just against their own Pay Rate/Charge Rate/Margin fields. Runs
    // automatically the moment the context resolves (autoCalculateRateAgreementLine), again live
    // whenever Pay Rate changes (handlePayRateChange/handleAwrPayRateChange), and again on
    // Recalculate/Save -- but NOT live as Margin/Charge Rate themselves are typed, only once one
    // of those triggers fires. Per field:
    //  - Fixed calc type: Margin is always forced to the Line's own Margin_Value__c, and Charge
    //    Rate is always (re)computed forward from Pay Rate + that fixed Margin -- never the other
    //    way around, so editing Charge Rate (or Pay Rate) can never change Margin for a Fixed line.
    //  - Max calc type: Charge Rate is computed forward from Margin UNLESS Charge Rate was the
    //    last field the user actually edited, in which case Margin is instead derived from it.
    //    Changing Pay Rate resets that back to "forward from Margin" -- see the callers, which
    //    reset lastEditedRateField/awrLastEditedRateField to 'margin' first -- since a Charge Rate
    //    typed against the OLD Pay Rate is no longer meaningful once Pay Rate changes.
    // Either way, the final Pay/Charge pair is always sent to calculateRateAgreementMargin --
    // reusing rateLineTriggerCustomHandler's own validateMarginAgainstLine -- as the authoritative
    // check, so this can never approve something the trigger would reject on save. Returns true
    // only when that check passes.
    async calculateAndValidateRateAgreementLine(isAwr) {
        const ctx = this.rateAgreementLineContext;
        if (!ctx || ctx.errorMessage) {
            return this.setCalcError(isAwr, ctx?.errorMessage || 'No applicable Rate Agreement Line was found.');
        }

        const label = isAwr ? 'AWR ' : '';
        const marginField = isAwr ? 'awrMargin' : 'lineMargin';
        const chargeField = isAwr ? 'awrChargeRate' : 'lineChargeRate';
        const payRate = parseFloat(isAwr ? this.awrPayRate : this.linePayRate);
        if (Number.isNaN(payRate)) {
            return this.setCalcError(isAwr, `Enter a ${label}Pay Rate before calculating.`);
        }

        const isFixed = this.isFixedCalcType(ctx.calcType);
        const isPercent = this.isPercentCalcType(ctx.calcType);
        const lastEdited = isAwr ? this.awrLastEditedRateField : this.lastEditedRateField;

        if (isFixed) {
            this[marginField] = ctx.marginValue;
        }

        let chargeRate;
        if (isFixed || lastEdited !== 'charge') {
            const margin = parseFloat(this[marginField]);
            if (Number.isNaN(margin)) {
                return this.setCalcError(isAwr, `Enter a ${label}Margin before calculating.`);
            }
            const totalCost = this.getTotalCostFor(payRate);
            chargeRate = Number((isPercent ? totalCost * (1 + margin / 100) : totalCost + margin).toFixed(2));
            this[chargeField] = chargeRate;
        } else {
            chargeRate = parseFloat(this[chargeField]);
            if (Number.isNaN(chargeRate)) {
                return this.setCalcError(isAwr, `Enter a ${label}Charge Rate before calculating.`);
            }
        }

        this.isCalculatingLine = true;
        try {
            const result = await calculateRateAgreementMargin({
                rateAgreementLineId: ctx.rateAgreementLineId,
                workerType: ctx.workerType,
                payRate,
                chargeRate,
                payScaleMin: ctx.payScaleMin,
                payScaleMax: ctx.payScaleMax
            });
            if (result.errorMessage) {
                return this.setCalcError(isAwr, result.errorMessage);
            }
            if (!isFixed) {
                // Max calc type -- reflect the server's own computed margin back so the (still
                // editable) Margin field always matches what was actually validated. Coerced with
                // Number() first -- an Apex Decimal can come back over the wire as a numeric
                // string, and String has no .toFixed().
                const computedMargin = isPercent ? result.marginPercent : result.marginAmount;
                if (computedMargin !== null && computedMargin !== undefined) {
                    this[marginField] = Number(computedMargin).toFixed(2);
                }
            }
            return this.setCalcError(isAwr, undefined);
        } catch (error) {
            return this.setCalcError(isAwr, this.getErrorMessage(error));
        } finally {
            this.isCalculatingLine = false;
        }
    }

    // Records (or, with no message, clears) the inline error for the main Rate Line or its AWR
    // modifier -- see lineErrors/awrErrorMessage. Returns true only when cleared, so the pipeline
    // can `return this.setCalcError(...)` for both outcomes.
    setCalcError(isAwr, message) {
        this[isAwr ? 'awrCalcError' : 'lineCalcError'] = message;
        return !message;
    }

    // Shared by the inline "Calculate" button and the footer "Recalculate" button in Rate
    // Agreement mode -- validates the main Rate Line, then (if applied) the AWR modifier against
    // the SAME Rate Agreement Line, stopping at the first failure.
    async handleCalculateRateAgreementLine() {
        const lineOk = await this.calculateAndValidateRateAgreementLine(false);
        if (!lineOk) {
            return;
        }
        if (this.awrApplies) {
            const awrOk = await this.calculateAndValidateRateAgreementLine(true);
            if (!awrOk) {
                return;
            }
        }
        this.showToast('Success', 'Recalculated.', 'success');
    }

    openViewEmployerOnCostModal() {
        this.showViewEmployerOnCostModal = true;
    }

    closeViewEmployerOnCostModal() {
        this.showViewEmployerOnCostModal = false;
    }

    openClonePageModal(event) {
        this.clonePageSourceId = event.currentTarget.dataset.pageId;
        // Defaults to the source Page's own Name -- still editable in the modal.
        const source = this.pages.find((p) => p.page.Id === this.clonePageSourceId);
        this.clonePageName = source?.page.Name || '';
        this.clonePageEffectiveDate = undefined;
        this.showClonePageModal = true;
    }

    closeClonePageModal() {
        this.showClonePageModal = false;
        this.clonePageSourceId = undefined;
        this.clonePageName = '';
        this.clonePageEffectiveDate = undefined;
    }

    handleClonePageNameChange(event) {
        this.clonePageName = event.target.value;
    }

    handleClonePageEffectiveDateChange(event) {
        this.clonePageEffectiveDate = event.target.value;
    }

    async handleConfirmClonePage() {
        if (!this.clonePageName || !this.clonePageName.trim()) {
            this.showToast('Error', 'Enter a name for the cloned Page.', 'error');
            return;
        }
        if (!this.clonePageEffectiveDate) {
            this.showToast('Error', 'Enter an Effective Date for the cloned Page.', 'error');
            return;
        }
        this.isCloningPage = true;
        try {
            await clonePage({
                sourcePageId: this.clonePageSourceId,
                newPageName: this.clonePageName.trim(),
                newValidFromDate: this.clonePageEffectiveDate
            });
            this.showToast(
                'Success',
                'Page cloned, with its Rate Lines and AWR modifiers. The source Page has been ended the day before this Effective Date.',
                'success'
            );
            this.closeClonePageModal();
            await refreshApex(this.wiredPagesResult);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isCloningPage = false;
        }
    }

    openEditPageModal(event) {
        const pageId = event.currentTarget.dataset.pageId;
        const target = this.pages.find((p) => p.page.Id === pageId);
        this.editPageId = pageId;
        this.editPageName = target?.page.Name;
        this.editPageValidFromDate = target?.page.sirenum__Valid_From_Date__c;
        this.editPageValidUntilDate = target?.page.sirenum__Valid_Until_Date__c;
        this.showEditPageModal = true;
    }

    closeEditPageModal() {
        this.showEditPageModal = false;
        this.editPageId = undefined;
        this.editPageName = undefined;
        this.editPageValidFromDate = undefined;
        this.editPageValidUntilDate = undefined;
    }

    handleEditPageNameChange(event) {
        this.editPageName = event.target.value;
    }

    handleEditPageValidFromDateChange(event) {
        this.editPageValidFromDate = event.target.value;
    }

    async handleSavePageEdit() {
        this.isSavingPageEdit = true;
        try {
            await updateRecord({
                fields: {
                    Id: this.editPageId,
                    [RATE_CARD_PAGE_NAME_FIELD.fieldApiName]: this.editPageName,
                    [RATE_CARD_PAGE_VALID_FROM_FIELD.fieldApiName]: this.editPageValidFromDate
                }
            });
            this.showToast('Success', 'Rate Card Page updated.', 'success');
            this.closeEditPageModal();
            await refreshApex(this.wiredPagesResult);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSavingPageEdit = false;
        }
    }

    // Employer On Cost mode's Recalculate prerequisites -- derived live from the form, so once
    // eocRecalcAttempted is set the inline error disappears the moment the missing value is filled.
    get eocRecalcPrereqError() {
        if (!this.selectedRateAgreementId) {
            return 'Select an Employer On Cost before recalculating.';
        }
        if (!this.lineMarginType) {
            return 'Select a Margin Type before recalculating.';
        }
        if (Number.isNaN(parseFloat(this.linePayRate))) {
            return 'Enter a Pay Rate before recalculating.';
        }
        const hasMargin = !Number.isNaN(parseFloat(this.lineMargin));
        const hasCharge = !Number.isNaN(parseFloat(this.lineChargeRate));
        if (!hasMargin && !hasCharge) {
            return 'Enter a Margin or a Charge Rate before recalculating.';
        }
        return undefined;
    }

    // Every inline error for the main Rate Line, shown as one block above the Pay/Charge Rate
    // group instead of toasts.
    get lineErrors() {
        const messages = [
            this.saveLineError,
            this.showEmployerOnCost && this.eocRecalcAttempted ? this.eocRecalcPrereqError : undefined,
            this.lineCalcError
        ].filter((message) => !!message);
        return [...new Set(messages)];
    }

    get hasLineErrors() {
        return this.lineErrors.length > 0;
    }

    // Shown inside the AWR box -- only while AWR still applies.
    get awrErrorMessage() {
        return this.awrApplies ? this.awrCalcError : undefined;
    }

    // Manual "Recalculate" button -- reports exactly which prerequisite is missing (inline, see
    // lineErrors) instead of silently doing nothing, since recalculate() itself just returns early
    // when it can't compute.
    handleRecalculateClick() {
        this.eocRecalcAttempted = true;
        if (this.eocRecalcPrereqError) {
            return;
        }
        this.eocRecalcAttempted = false;
        this.recalculate();
        this.recalculateAwr();
        this.showToast('Success', 'Recalculated.', 'success');
    }

    handleUnitChange(event) {
        this.lineUnit = event.detail.value;
    }

    handleStartHourChange(event) {
        this.lineStartHour = event.target.value;
    }

    handleEndHourChange(event) {
        this.lineEndHour = event.target.value;
    }

    handleDayTypeChange(event) {
        this.lineDayType = event.detail.value;
    }

    // "Edit / New Employer On Cost" opens employerOnCostManager embedded in a modal (not a new
    // tab) -- pre-selected with whichever Rate Agreement is currently chosen above, if any.
    openEmployerOnCostModal() {
        this.showEmployerOnCostModal = true;
    }

    // Closing is the natural "I'm done editing" moment, so refresh and recalculate here instead
    // of requiring a separate manual refresh action -- see handleRefreshEmployerOnCost below.
    async closeEmployerOnCostModal() {
        this.showEmployerOnCostModal = false;
        await this.handleRefreshEmployerOnCost();
    }

    // Sweeps every required field in the Add Rate Line form (marked with the required-field
    // class) and reports validity on each, so the user sees every missing field at once rather
    // than one toast per attempt.
    validateRequiredFields() {
        const fields = this.template.querySelectorAll('.required-field');
        let allValid = true;
        fields.forEach((field) => {
            if (!field.reportValidity()) {
                allValid = false;
            }
        });
        return allValid;
    }

    // Built without lightning-record-edit-form so Unit/Start Hour/End Hour/Day Type/Margin Type
    // can be added, Day Type can be omitted in restricted mode, and Margin Type can be omitted
    // when the Contract has its own Rate Agreement (see showEmployerOnCost). When editingLineId
    // is set (per-line Edit button), updates that record in place instead of creating a new one
    // -- Page and Sort Order stay untouched in that case. sirenum__SortOrder__c (required, no
    // default) is appended after this Page's existing lines on create, matching the same
    // convention used for Rate Card Page's own Sort Order in rateManager.
    async handleSaveLine() {
        this.saveLineError = undefined;
        if (!this.validateRequiredFields()) {
            return;
        }

        // Rate Agreement mode's own sanity check -- re-runs the exact same Calculate pipeline
        // (main Rate Line, then AWR if applied) and refuses to save unless both pass, same as the
        // Calculate/Recalculate buttons. The trigger validates again independently on the actual
        // DML below regardless -- this is purely to fail fast with a clear message.
        if (this.isRateAgreementMode) {
            const lineOk = await this.calculateAndValidateRateAgreementLine(false);
            if (!lineOk) {
                return;
            }
            if (this.awrApplies) {
                const awrOk = await this.calculateAndValidateRateAgreementLine(true);
                if (!awrOk) {
                    return;
                }
            }
        }

        this.isSavingLine = true;

        try {
            const fields = {
                [RATE_LINE_STANDARD_RATE_TYPE_FIELD.fieldApiName]: this.selectedStandardRateTypeId,
                [RATE_LINE_CODE_FIELD.fieldApiName]: this.derivedCode,
                [RATE_LINE_RATE_AGREEMENT_FIELD.fieldApiName]: this.selectedRateAgreementId,
                [RATE_LINE_UNIT_FIELD.fieldApiName]: this.lineUnit,
                [RATE_LINE_START_HOUR_FIELD.fieldApiName]: this.lineStartHour,
                [RATE_LINE_END_HOUR_FIELD.fieldApiName]: this.lineEndHour,
                [RATE_LINE_PAY_RATE_FIELD.fieldApiName]: this.linePayRate,
                [RATE_LINE_CHARGE_RATE_FIELD.fieldApiName]: this.lineChargeRate,
                [RATE_LINE_MARGIN_TYPE_FIELD.fieldApiName]: this.lineMarginType
            };
            fields[RATE_LINE_MARGIN_FIELD.fieldApiName] = this.lineMargin;
            if (this.showDayType) {
                fields[RATE_LINE_DAY_TYPE_FIELD.fieldApiName] = this.lineDayType;
            }

            let lineId;
            if (this.editingLineId) {
                fields.Id = this.editingLineId;
                await updateRecord({ fields });
                lineId = this.editingLineId;
            } else {
                const targetPage = this.pages.find((p) => p.page.Id === this.addLineTargetPageId);
                const existingOrders = (targetPage?.lines || [])
                    .map((entry) => entry.line.sirenum__SortOrder__c)
                    .filter((value) => value !== null && value !== undefined);
                fields[RATE_LINE_PAGE_FIELD.fieldApiName] = this.addLineTargetPageId;
                fields[RATE_LINE_SORT_ORDER_FIELD.fieldApiName] = existingOrders.length ? Math.max(...existingOrders) + 1 : 1;
                const savedLine = await createRecord({ apiName: RATE_LINE_OBJECT.objectApiName, fields });
                lineId = savedLine.id;
            }

            await this.saveAwrModifier(lineId);

            const wasEditing = !!this.editingLineId;
            this.isSavingLine = false;
            this.closeAddLineModal();
            this.showToast('Success', wasEditing ? 'Rate Line updated.' : 'Rate Line added.', 'success');
            await refreshApex(this.wiredPagesResult);
        } catch (error) {
            this.isSavingLine = false;
            // Inline (see lineErrors), e.g. the trigger's own margin validation.
            this.saveLineError = this.getErrorMessage(error);
        }
    }

    // AWR (sirenum__Rate_Modifier__c linked to the 'AWR' sirenum__Rate_Modifier_Type__c) lifecycle
    // for this Rate Line -- toggled ON creates/updates it, toggled OFF (and saved) deletes any
    // existing one.
    async saveAwrModifier(lineId) {
        if (this.awrApplies) {
            const fields = {
                [RATE_MODIFIER_RATE_LINE_FIELD.fieldApiName]: lineId,
                [RATE_MODIFIER_TYPE_FIELD.fieldApiName]: this.awrRateModifierTypeId,
                [RATE_MODIFIER_PAY_RATE_FIELD.fieldApiName]: this.awrPayRate,
                [RATE_MODIFIER_CHARGE_RATE_FIELD.fieldApiName]: this.awrChargeRate,
                [RATE_MODIFIER_MARGIN_TYPE_FIELD.fieldApiName]: this.awrMarginType,
                [RATE_MODIFIER_MARGIN_FIELD.fieldApiName]: this.awrMargin
            };
            if (this.existingAwrModifierId) {
                fields.Id = this.existingAwrModifierId;
                await updateRecord({ fields });
            } else {
                await createRecord({ apiName: RATE_MODIFIER_OBJECT.objectApiName, fields });
            }
        } else if (this.existingAwrModifierId) {
            await deleteRecord(this.existingAwrModifierId);
        }
    }

    showError(error) {
        this.showToast('Error', this.getErrorMessage(error), 'error');
    }

    // Same normalized shape used across the Rate Manager components -- checks
    // output.fieldErrors/output.errors first, since createRecord()'s own error.body.message is
    // often just a generic placeholder.
    getErrorMessage(error) {
        const output = error?.body?.output ?? error?.output;
        if (output?.fieldErrors && Object.keys(output.fieldErrors).length) {
            return Object.values(output.fieldErrors).flat().map((e) => e.message).join(', ');
        }
        if (output?.errors?.length) {
            return output.errors.map((e) => e.message).join(', ');
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}