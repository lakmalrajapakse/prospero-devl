import { LightningElement, api, wire } from 'lwc';
import { getRecord, updateRecord, createRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRateCardPages from '@salesforce/apex/RateManagerController.getRateCardPages';
import getAgreementDetails from '@salesforce/apex/MarginCalculatorController.getAgreementDetails';
import JOB_ROLE_RATE_CARD_FIELD from '@salesforce/schema/sirenum__Team__c.sirenum__Rate_Card__c'
import PLACEMENT_RATE_CARD_FIELD from '@salesforce/schema/sirenum__Placement__c.sirenum__Rate_Card__c'
import PLACEMENT_START_DATE_FIELD from '@salesforce/schema/sirenum__Placement__c.sirenum__Start_Date__c'
// Job Role default disabled for now -- see the commented-out wires/method below. Placement
// should not default from its Job Role's Rate Card in any scenario as of now.
// import PLACEMENT_JOB_ROLE_FIELD from '@salesforce/schema/sirenum__Placement__c.sirenum__Job_Role__c'
import SHIFT_PLACEMENT_FIELD from '@salesforce/schema/sirenum__Shift__c.sirenum__Placement__c'
import SHIFT_DATE_FIELD from '@salesforce/schema/sirenum__Shift__c.sirenum__Shift_Date__c'
import SHIFT_NAME_FIELD from '@salesforce/schema/sirenum__Shift__c.Name'
import PLACEMENT_NAME_FIELD from '@salesforce/schema/sirenum__Placement__c.Name'
import RATE_CARD_OBJECT from '@salesforce/schema/sirenum__Rate_Card__c'
import RATE_CARD_NAME_FIELD from '@salesforce/schema/sirenum__Rate_Card__c.Name'
import RATE_CARD_PAGE_OBJECT from '@salesforce/schema/sirenum__Rate_Card_Page__c'
import RATE_CARD_PAGE_NAME_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.Name'
import RATE_CARD_PAGE_RATE_CARD_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Rate_Card__c'
import RATE_CARD_PAGE_CONDITION_SUGGESTIONS_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Condition_Suggestions__c'
import RATE_CARD_PAGE_CONDITION_OPERATOR_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Condition_Operator__c'
import RATE_CARD_PAGE_CONDITION_VALUE_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Condition_value__c'
import RATE_CARD_PAGE_VALID_FROM_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__Valid_From_Date__c'
import RATE_CARD_PAGE_SORT_ORDER_FIELD from '@salesforce/schema/sirenum__Rate_Card_Page__c.sirenum__SortOrder__c'

const JOB_ROLE_OBJECT = 'sirenum__Team__c'
const SHIFT_OBJECT = 'sirenum__Shift__c'
const PLACEMENT_OBJECT = 'sirenum__Placement__c'

// The Shift-condition page is identified by Condition_Suggestions__c = 'Id' (the "Shift ID"
// picklist entry) with Condition_Operator__c = 'Equal to' and Condition_value__c holding the
// Shift's own Id.
const SHIFT_CONDITION_SUGGESTION_VALUE = 'Id'
const SHIFT_CONDITION_OPERATOR_VALUE = 'Equal to'

export default class RateManager extends LightningElement {
    @api recordId
    @api objectApiName
    // Set from a Screen Flow (see rateManager.js-meta.xml) -- the flow screen already shows its
    // own title, so this component's own title bar and card chrome are hidden to avoid two.
    @api isCalledFromFlow = false
    isLoading = true

    rateCardObject = RATE_CARD_OBJECT
    cardFields = [RATE_CARD_NAME_FIELD]
    jobRoleRecordId
    placementRecordId
    shiftRecordId

    // Resolved Rate Card to display, regardless of which object it came from (Job Role's own
    // field, Placement's own field, or defaulted from the Placement's Job Role).
    RateCardId
    // The Placement's own Name -- used as the new Rate Card's Name when auto-created directly
    // from the Placement (no Job Role default for now -- see wire 4 below).
    placementName
    // Id of a Rate Card Page this component just created -- via the Placement auto-create
    // cascade, or "Create Shift Page". Passed to the child so it can auto-open its Add Rate Line modal for
    // that specific Page while it still has zero lines, so a freshly created empty Page never
    // dead-ends.
    justCreatedPageId

    // Job Role default disabled for now -- see wire 4 (commented out) below.
    // placementJobRoleId

    // Set (via wire 3b/6c below) when this Placement's Contract has a Rate Agreement but the
    // Placement can't actually be validated against it (no Job Role Scale, or no Rate Agreement
    // Scale Definition on that Scale) -- rateLineTriggerCustomHandler itself requires this before
    // it can even resolve a Rate Agreement Version, so Rate Card/Page/Rate Line creation is
    // blocked entirely and this is shown as an on-screen error instead. Null/undefined when the
    // Contract has no Rate Agreement at all -- that's the unaffected Employer On Cost route.
    placementAgreementBlockingError
    shiftPlacementAgreementBlockingError

    // ---- Shift-only state ----
    // The Shift's own Placement lookup, Shift Date, and Name (used as the new Shift Rate Card
    // Page's own Name), loaded once the object is a Shift.
    shiftPlacementId
    shiftDate
    shiftName
    // True only when the Shift has no Placement at all -- nothing can be resolved, shown as an
    // error instead of the usual flows.
    shiftPlacementMissing
    // Job Role default disabled for now -- see wire 6b (commented out) below.
    // shiftPlacementJobRoleId
    // Gates the Rate Card Pages wire below -- only populated once the Shift's Placement is
    // known to already have a Rate Card of its own.
    shiftPlacementRateCardId
    // True only when the Shift's Placement has no Rate Card at all -- offers "Create Placement
    // Rate Card" (see handleCreateRateCard).
    shiftNeedsRateCardCreation
    // The Shift's Placement's Name -- used as the Name of a Rate Card / Placement level Page
    // created from the Shift.
    shiftPlacementName
    // True once wire 7 confirms the Rate Card has no Page yet for this Shift -- the child then
    // shows the Placement level Page valid on the Shift's date, with "Create Shift Page" on each
    // of its Rate Lines (see handleCreateShiftPage), or, when there's no Placement level Page at
    // all, "Create Placement Rate Card Page" is offered instead.
    showPlacementLineSelection
    // The Placement Line whose "Create Shift Page" was clicked -- prefills the auto-opened Add
    // Rate Line modal's form on the new Shift Page.
    prefillLineId
    // Guards the Shift's create handlers against a double click creating duplicate records.
    isCreatingPage = false
    // Resolved Shift-condition Rate Card Page -- the Shift equivalent of RateCardId. Always
    // rendered in c-margin-calculator-component's restricted (view/edit, no Add) mode.
    RateCardPageId
    // Sibling pages already under the Rate Card, from wire 7 -- used only to compute
    // sirenum__SortOrder__c (required, no default) for a newly created Shift page, which is
    // appended after everything else.
    ratePages = []
    // The wire 7 provisioned value, kept so refreshApex() can bypass its cache after creating
    // a new Page -- see the comment on that wire.
    wiredRateCardPagesResult




    /// Wire 1 to get the Object API Name
    // Fetch the record data using the recordId
    @wire(getRecord, { recordId: '$recordId', layoutTypes: ['Full'], modes: ['View'] })
        wiredRecord({ error, data }) {
            if (data) {
                // Extract the object API name from the record's metadata
                this.objectApiName = data.apiName;
                if( this.objectApiName ==JOB_ROLE_OBJECT){
                    this.jobRoleRecordId = this.recordId;
                } else if(this.objectApiName === SHIFT_OBJECT){
                    this.shiftRecordId = this.recordId
                } else if(this.objectApiName === PLACEMENT_OBJECT){
                    this.placementRecordId = this.recordId
                }

            } else if (error) {
                console.error('Error fetching record metadata:', error);
                this.isLoading = false;
            }
        }

    // Wire 2: Job Role only -- once we know the object is a Job Role, check whether it
    // already has a Rate Card linked.
    @wire(getRecord, { recordId: '$jobRoleRecordId', fields: [JOB_ROLE_RATE_CARD_FIELD] })
        wiredJobRoleRecord({ error, data }) {
            if (data) {
                this.RateCardId = data.fields.sirenum__Rate_Card__c.value;
                this.isLoading = false
            } else if (error) {
                console.error('Error fetching Job Role Rate Card:', error);
                 this.isLoading = false
            }
        }

    // Wire 3: Placement only -- once we know the object is a Placement, check whether it
    // already has a Rate Card of its own. Job Role default is disabled for now (see wire 4,
    // commented out below) -- a Placement with no Rate Card just shows the create form.
    @wire(getRecord, { recordId: '$placementRecordId', fields: [PLACEMENT_RATE_CARD_FIELD, PLACEMENT_START_DATE_FIELD, PLACEMENT_NAME_FIELD] })
        wiredPlacementRecord({ error, data }) {
            if (data) {
                const ownRateCardId = data.fields.sirenum__Rate_Card__c.value;
                this.placementName = data.fields.Name.value;
                this.placementStartDate = data.fields.sirenum__Start_Date__c.value;
                if (ownRateCardId) {
                    this.RateCardId = ownRateCardId;
                }
                this.isLoading = false;
            } else if (error) {
                console.error('Error fetching Placement Rate Card:', error);
                this.isLoading = false;
            }
        }

    // Wire 3b: Placement's Rate-Agreement blocking check -- see placementAgreementBlockingError.
    @wire(getAgreementDetails, { placementId: '$placementRecordId' })
        wiredPlacementAgreementDetails({ data, error }) {
            if (data) {
                this.placementAgreementBlockingError = data.blockingError;
            } else if (error) {
                console.error('Error fetching Placement Agreement Details:', error);
            }
        }

    // Wire 4: Placement's Job Role -- disabled for now. Placement should not default from its
    // Job Role's Rate Card in any scenario as of now.
    // @wire(getRecord, { recordId: '$placementJobRoleId', fields: [JOB_ROLE_RATE_CARD_FIELD] })
    //     wiredPlacementJobRoleRecord({ error, data }) {
    //         if (data) {
    //             const jobRoleRateCardId = data.fields.sirenum__Rate_Card__c.value;
    //             if (jobRoleRateCardId) {
    //                 this.defaultPlacementRateCardFromJobRole(this.placementRecordId, jobRoleRateCardId);
    //             } else {
    //                 this.isLoading = false;
    //             }
    //         } else if (error) {
    //             console.error('Error fetching Placement\'s Job Role Rate Card:', error);
    //             this.isLoading = false;
    //         }
    //     }

    // Wire 5: Shift only -- once we know the object is a Shift, load its own Placement lookup
    // and Shift Date. Gates wire 6 below.
    @wire(getRecord, { recordId: '$shiftRecordId', fields: [SHIFT_PLACEMENT_FIELD, SHIFT_DATE_FIELD, SHIFT_NAME_FIELD] })
        wiredShiftRecord({ error, data }) {
            if (data) {
                this.shiftPlacementId = data.fields.sirenum__Placement__c.value;
                this.shiftDate = data.fields.sirenum__Shift_Date__c.value;
                this.shiftName = data.fields.Name.value;
                if (!this.shiftPlacementId) {
                    this.shiftPlacementMissing = true;
                    this.isLoading = false; // Shift isn't linked to a Placement -- nothing to resolve.
                }
            } else if (error) {
                console.error('Error fetching Shift record:', error);
                this.isLoading = false;
            }
        }

    // Wire 6: Shift's Placement -- check whether it already has a Rate Card of its own. Job Role
    // default is disabled for now (see wire 6b, commented out below). If it does, gate wire 7.
    placementStartDate
    @wire(getRecord, { recordId: '$shiftPlacementId', fields: [PLACEMENT_RATE_CARD_FIELD, PLACEMENT_NAME_FIELD, PLACEMENT_START_DATE_FIELD] })
        wiredShiftPlacementRecord({ error, data }) {
            if (data) {
                const rateCardId = data.fields.sirenum__Rate_Card__c.value;
                this.shiftPlacementName = data.fields.Name.value;
                // Valid From for a Placement level Page created from the Shift -- see createNoConditionPage.
                this.placementStartDate = data.fields.sirenum__Start_Date__c.value;
                if (rateCardId) {
                    // Gates wire 7 below -- resolved there once the Rate Card's Pages are known.
                    this.shiftPlacementRateCardId = rateCardId;
                } else {
                    this.shiftNeedsRateCardCreation = true;
                    this.isLoading = false;
                }
            } else if (error) {
                console.error('Error fetching Shift\'s Placement Rate Card:', error);
                this.isLoading = false;
            }
        }

    // Wire 6c: Shift's Placement's Rate-Agreement blocking check -- see
    // shiftPlacementAgreementBlockingError.
    @wire(getAgreementDetails, { placementId: '$shiftPlacementId' })
        wiredShiftPlacementAgreementDetails({ data, error }) {
            if (data) {
                this.shiftPlacementAgreementBlockingError = data.blockingError;
            } else if (error) {
                console.error('Error fetching Shift Placement Agreement Details:', error);
            }
        }

    // Wire 6b: Shift's Placement's Job Role -- disabled for now. Placement should not default
    // from its Job Role's Rate Card in any scenario as of now.
    // @wire(getRecord, { recordId: '$shiftPlacementJobRoleId', fields: [JOB_ROLE_RATE_CARD_FIELD] })
    //     wiredShiftPlacementJobRoleRecord({ error, data }) {
    //         if (data) {
    //             const jobRoleRateCardId = data.fields.sirenum__Rate_Card__c.value;
    //             if (jobRoleRateCardId) {
    //                 this.defaultPlacementRateCardFromJobRole(this.shiftPlacementId, jobRoleRateCardId);
    //             } else {
    //                 this.shiftNeedsRateCardCreation = true;
    //                 this.isLoading = false;
    //             }
    //         } else if (error) {
    //             console.error('Error fetching Shift\'s Placement\'s Job Role Rate Card:', error);
    //             this.isLoading = false;
    //         }
    //     }

    // Wire 7: Rate Card Pages under the Shift's Placement Rate Card -- a direct Apex SOQL query
    // (not lightning/uiRelatedListApi's getRelatedListRecords, which silently returned an empty
    // list for this relationship and caused duplicate Shift Pages to be created on every load).
    // Looks for a page whose condition already targets this Shift.
    @wire(getRateCardPages, { rateCardId: '$shiftPlacementRateCardId' })
        wiredRateCardPages(result) {
            // Captured whole so refreshApex() can force-bypass this cacheable method's cache
            // after we create a new Page -- otherwise a stale cached list could make a later
            // reload think that Page doesn't exist yet and create another duplicate.
            this.wiredRateCardPagesResult = result;
            const { error, data } = result;
            if (data) {
                this.ratePages = data;
                this.resolveShiftRateCardPage(data);
            } else if (error) {
                console.error('Error fetching Rate Card Pages:', error);
                this.isLoading = false;
            }
        }

    // This Shift's own page, if one exists, is displayed directly -- otherwise the child lists the
    // Placement's valid Page for the user to create one from (see showPlacementLineSelection).
    resolveShiftRateCardPage(pages){
        const conditionSuggestionsApi = RATE_CARD_PAGE_CONDITION_SUGGESTIONS_FIELD.fieldApiName;
        const conditionValueApi = RATE_CARD_PAGE_CONDITION_VALUE_FIELD.fieldApiName;

        const shiftPage = pages.find((page) =>
            page[conditionSuggestionsApi] === SHIFT_CONDITION_SUGGESTION_VALUE &&
            page[conditionValueApi] === this.shiftRecordId
        );
        this.RateCardPageId = shiftPage ? shiftPage.Id : undefined;
        this.showPlacementLineSelection = !shiftPage;
        this.isLoading = false;
    }




    // Job Role only -- fires once lightning-record-form successfully inserts the new Rate Card.
    // Creating the record alone doesn't link it to anything, so link it onto the Job Role too.
    // Placement and Shift no longer use this form -- see handleCreateRateCard below.
    async handleRateCardCreated(event){
        const newRateCardId = event.detail.id;
        try {
            await updateRecord({
                fields: {
                    Id: this.jobRoleRecordId,
                    [JOB_ROLE_RATE_CARD_FIELD.fieldApiName]: newRateCardId
                }
            });
            this.RateCardId = newRateCardId;
            this.showToast('Success', 'Rate Card created and linked to this Job Role.', 'success');
        } catch (error) {
            this.showToast('Rate Card was created but could not be linked to this Job Role', this.getErrorMessage(error), 'error');
        }
    }

    handleRateCardError(event){
        this.showToast('Error creating Rate Card', this.getErrorMessage(event.detail), 'error');
    }

    // Placement only -- no Name prompt, the new Rate Card is always named after the Placement.
    // Also auto-creates its Placement level Page and flags the child to open the Add Rate Line
    // modal immediately, so the user lands straight on creating their first Rate Line.
    async handleCreateRateCard(){
        this.isLoading = true;
        try {
            const rateCard = await createRecord({
                apiName: RATE_CARD_OBJECT.objectApiName,
                fields: {
                    [RATE_CARD_NAME_FIELD.fieldApiName]: this.placementName
                }
            });
            await updateRecord({
                fields: {
                    Id: this.placementRecordId,
                    [PLACEMENT_RATE_CARD_FIELD.fieldApiName]: rateCard.id
                }
            });

            // Finish creating the Page BEFORE setting RateCardId -- that's what mounts the child
            // (hasRateCard becomes true), so it must not render until the Page already exists and
            // justCreatedPageId is already set, or its first wire fetch races the Page's own
            // creation and its initial auto-open check runs before this prop arrives (both are
            // only evaluated once, when data first resolves).
            const pageId = await this.createNoConditionPage(rateCard.id, this.placementName);
            this.justCreatedPageId = pageId;
            this.RateCardId = rateCard.id;
            this.isLoading = false;
            this.showToast('Success', 'Rate Card created and linked to this Placement.', 'success');
        } catch (error) {
            this.showToast('Could not create a Rate Card for this Placement', this.getErrorMessage(error), 'error');
            this.isLoading = false;
        }
    }

    // Defaults a Placement onto its Job Role's existing Rate Card -- disabled for now. Placement
    // should not default from its Job Role's Rate Card in any scenario as of now.
    // async defaultPlacementRateCardFromJobRole(targetPlacementId, jobRoleRateCardId){
    //     try {
    //         await updateRecord({
    //             fields: {
    //                 Id: targetPlacementId,
    //                 [PLACEMENT_RATE_CARD_FIELD.fieldApiName]: jobRoleRateCardId
    //             }
    //         });
    //         this.showToast('Success', 'Rate Card defaulted from this Placement\'s Job Role.', 'success');
    //         if (this.shiftRecordId) {
    //             this.shiftPlacementRateCardId = jobRoleRateCardId;
    //         } else {
    //             this.RateCardId = jobRoleRateCardId;
    //             this.isLoading = false;
    //         }
    //     } catch (error) {
    //         this.showToast('Could not default Rate Card from the Job Role', this.getErrorMessage(error), 'error');
    //         this.isLoading = false;
    //     }
    // }

    // "Create Shift Page" clicked on one of the Placement's Rate Lines (the child fires
    // 'createshiftpage' with that Line's Id) -- a new page on the same Rate Card, conditioned on
    // this Shift's Id, effective from the Shift's own date. prefillLineId and justCreatedPageId
    // are both in place before RateCardPageId is set, since that's what swaps in the restricted
    // child -- it then auto-opens the Add Rate Line modal on the new (still empty) Page,
    // prefilled from the clicked Line.
    async handleCreateShiftPage(event){
        if (this.isCreatingPage) {
            return;
        }
        this.isCreatingPage = true;
        this.isLoading = true;
        try {
            const pageId = await this.createShiftConditionPage(this.shiftPlacementRateCardId);
            this.prefillLineId = event.detail.lineId;
            this.justCreatedPageId = pageId;
            await refreshApex(this.wiredRateCardPagesResult);
            this.RateCardPageId = pageId;
            this.showPlacementLineSelection = false;
            this.showToast('Success', 'Shift Rate Card Page created.', 'success');
        } catch (error) {
            this.showToast('Could not create the Shift Rate Card Page', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
            this.isCreatingPage = false;
        }
    }

    // Shift whose Placement has no Rate Card at all -- creates one (named after the Placement),
    // links it onto the Placement, and creates its Placement level Page too. justCreatedPageId is
    // set BEFORE shiftPlacementRateCardId (which gates wire 7 and so mounts the child), so the
    // child auto-opens Add Rate Line on the new Page -- once that first Line exists, "Create
    // Shift Page" is available on it.
    async handleCreateShiftPlacementRateCard(){
        if (this.isCreatingPage) {
            return;
        }
        this.isCreatingPage = true;
        this.isLoading = true;
        try {
            const rateCard = await createRecord({
                apiName: RATE_CARD_OBJECT.objectApiName,
                fields: {
                    [RATE_CARD_NAME_FIELD.fieldApiName]: this.shiftPlacementName
                }
            });
            await updateRecord({
                fields: {
                    Id: this.shiftPlacementId,
                    [PLACEMENT_RATE_CARD_FIELD.fieldApiName]: rateCard.id
                }
            });
            this.justCreatedPageId = await this.createNoConditionPage(rateCard.id, this.shiftPlacementName);
            this.shiftNeedsRateCardCreation = false;
            this.shiftPlacementRateCardId = rateCard.id;
            this.showToast('Success', "Rate Card created and linked to this Shift's Placement.", 'success');
        } catch (error) {
            this.showToast("Could not create a Rate Card for this Shift's Placement", this.getErrorMessage(error), 'error');
            this.isLoading = false;
        } finally {
            this.isCreatingPage = false;
        }
    }

    // Shift whose Placement's Rate Card exists but has no Placement level Page -- creates one,
    // then the child (mounted once the refresh sees it -- see hasPlacementLevelPage) auto-opens
    // Add Rate Line on it, same as handleCreateShiftPlacementRateCard.
    async handleCreateShiftPlacementPage(){
        if (this.isCreatingPage) {
            return;
        }
        this.isCreatingPage = true;
        this.isLoading = true;
        try {
            const pageId = await this.createNoConditionPage(this.shiftPlacementRateCardId, this.shiftPlacementName);
            this.justCreatedPageId = pageId;
            await refreshApex(this.wiredRateCardPagesResult);
            // hasPlacementLevelPage is what swaps the button for the child -- don't leave it
            // depending on the refresh alone having picked the new Page up.
            if (!this.ratePages.some((page) => page.Id === pageId)) {
                this.ratePages = [...this.ratePages, { Id: pageId }];
            }
            this.showToast('Success', 'Placement Rate Card Page created.', 'success');
        } catch (error) {
            this.showToast('Could not create the Placement Rate Card Page', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
            this.isCreatingPage = false;
        }
    }

    // sirenum__SortOrder__c is required with no default. Convention: the Placement level page
    // always sorts first (0, or lower than any existing sibling), and Shift pages are appended
    // after everything else, in creation order.
    get existingSortOrders(){
        const sortOrderApi = RATE_CARD_PAGE_SORT_ORDER_FIELD.fieldApiName;
        return this.ratePages
            .map((page) => page[sortOrderApi])
            .filter((value) => value !== null && value !== undefined);
    }

    async createNoConditionPage(rateCardId, pageName){
        const existingOrders = this.existingSortOrders;
        const sortOrder = existingOrders.length ? Math.min(...existingOrders) - 1 : 0;
        const { id } = await createRecord({
            apiName: RATE_CARD_PAGE_OBJECT.objectApiName,
            fields: {
                [RATE_CARD_PAGE_RATE_CARD_FIELD.fieldApiName]: rateCardId,
                [RATE_CARD_PAGE_NAME_FIELD.fieldApiName]: pageName,
                [RATE_CARD_PAGE_SORT_ORDER_FIELD.fieldApiName]: sortOrder,
                [RATE_CARD_PAGE_VALID_FROM_FIELD.fieldApiName]: this.placementStartDate
            }
        });
        return id;
    }

    async createShiftConditionPage(rateCardId){
        const existingOrders = this.existingSortOrders;
        const sortOrder = existingOrders.length ? Math.max(...existingOrders) + 1 : 1;
        const { id } = await createRecord({
            apiName: RATE_CARD_PAGE_OBJECT.objectApiName,
            fields: {
                [RATE_CARD_PAGE_RATE_CARD_FIELD.fieldApiName]: rateCardId,
                [RATE_CARD_PAGE_NAME_FIELD.fieldApiName]: this.shiftName,
                [RATE_CARD_PAGE_CONDITION_SUGGESTIONS_FIELD.fieldApiName]: SHIFT_CONDITION_SUGGESTION_VALUE,
                [RATE_CARD_PAGE_CONDITION_OPERATOR_FIELD.fieldApiName]: SHIFT_CONDITION_OPERATOR_VALUE,
                [RATE_CARD_PAGE_CONDITION_VALUE_FIELD.fieldApiName]: this.shiftRecordId,
                [RATE_CARD_PAGE_VALID_FROM_FIELD.fieldApiName]: this.shiftDate,
                [RATE_CARD_PAGE_SORT_ORDER_FIELD.fieldApiName]: sortOrder
            }
        });
        return id;
    }

    ///// Getters
    get showCardHeader(){
        return !this.isCalledFromFlow;
    }

    get cardClass(){
        return this.isCalledFromFlow ? 'mc-card-flow' : 'slds-card mc-card';
    }

    get objectName(){
         return this.objectApiName === JOB_ROLE_OBJECT ? 'Job Role' : this.objectApiName === SHIFT_OBJECT ? 'Shift': 'Placement'
    }

    // Show the resolved Rate Card once one is known, otherwise prompt to create one.
    get hasRateCard(){
        return !!this.RateCardId;
    }

    // Shift only: show the resolved Rate Card Page once one is known.
    get hasRateCardPage(){
        return !!this.RateCardPageId;
    }

    // Shift only: whether the Rate Card already has a Placement level (no-condition) Page for the
    // child to list -- otherwise "Create Placement Rate Card Page" is offered instead.
    get hasPlacementLevelPage(){
        const conditionSuggestionsApi = RATE_CARD_PAGE_CONDITION_SUGGESTIONS_FIELD.fieldApiName;
        return this.ratePages.some((page) => !page[conditionSuggestionsApi]);
    }


    // Normalizes the handful of shapes LWC errors show up in (record-form's onerror payload,
    // an updateRecord()/createRecord() rejection, a plain Error) down to one displayable string.
    // Checks output.fieldErrors/output.errors FIRST -- updateRecord()'s own error.body.message is
    // often just a generic "An error occurred..." placeholder, while the actual validation rule
    // or required-field reason sits in output.fieldErrors/output.errors instead.
    getErrorMessage(error){
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


    /// Toast message
    showToast(title, message, variant){
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}