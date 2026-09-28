import { LightningElement, api, wire, track } from 'lwc';
import searchLookupRecords from '@salesforce/apex/ClientContactSearchController.searchLookupRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class CustomLookupComponent extends LightningElement {
    @api fieldApiName
    @api objectApiName
    @api whereClause
    @api fieldsToDisplay
    @api label
    @api placeholder
    @api helptext
    @api maxSelection

    // Component variables
    showDropdown = false
    searchTerm=''
    searchResults = []
    selectedRecords = []
    isLoading = false

    // Hanlder search method
   debounceTimeout

    // Handle Search with debounce
    handleSearch(event){

        this.searchTerm = event.target.value
        // Clear existing timeout
        window.clearTimeout(this.debounceTimeout)

        // Empty search handling
        if(!this.searchTerm){
            this.searchResults = []
            this.showDropdown = false
            return
        }
        // Debounce API call
        this.debounceTimeout = setTimeout(async () => {
            this.isLoading = true
            try {
                const results =
                    await searchLookupRecords({
                        objectApiName: this.objectApiName,
                        fieldApiName: this.fieldApiName,
                        searchTerm: this.searchTerm,
                        whereClause: this.whereClause
                    })
                // Remove already selected
                this.searchResults = results.filter(result => {
                                return !this.selectedRecords.some(selected =>
                                    selected.value === result.value
                                ) })

                this.showDropdown = true

            } catch(error){

                console.error(error)

            } finally {

                this.isLoading = false
            }

        }, 400)
    }
    // Handle the Selection of record
    handleSelect(event){

        const recordId = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;

        // Max selection validation
        if( this.maxSelection && this.selectedRecords.length >= this.maxSelection
        ){
            this.searchTerm=''
            this.showDropdown = false
            this.showMessage('Warning',`You can only select upto: ${this.maxSelection} records. Please ask your admin to increase the limit if you want to select more!.`,'warning');
            return
        }

        this.selectedRecords = [
            ...this.selectedRecords,
            {
                label,
                value: recordId
            }
        ];

        this.searchResults =this.searchResults.filter(record =>
                                                                record.value !== recordId
                                                            );

        this.searchTerm = '';
        this.showDropdown = false;

        this.dispatchLookupChange();
    }

    // Handle the removal of record from pill
    handleRemove(event){
        const recordId = event.detail.item.value;
        this.selectedRecords = this.selectedRecords.filter(record =>
                                                                    record.value !== recordId
                                                                );
        this.dispatchLookupChange();
    }

    /// Event to Parent
    dispatchLookupChange(){
        this.dispatchEvent( new CustomEvent('lookupchange', { detail: {
                                            fieldApiName:
                                                this.fieldApiName,
                                            value:
                                                this.selectedRecords.map(record =>
                                                    record.value
                                                )
                                        }
                                    })
                                );
    }

    // Getters
    get dropdownClass(){
        let classes = 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click'
        if(this.showDropdown){
            classes += ' slds-is-open'
        }
        return classes
    }

    get hasResults(){
        return this.searchResults &&
            this.searchResults.length > 0
    }
    // Toast
    showMessage(title, message, variant){
        const evt = new ShowToastEvent({
            title,message,variant
        })
        this.dispatchEvent(evt);
    }
}