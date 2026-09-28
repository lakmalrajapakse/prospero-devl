import { LightningElement, api, wire, track } from 'lwc';

export default class DynamicFiltersClientSearch extends LightningElement {
@api filters=[]

searchCriteria = {}




///Change Handler
    changeHandler(event){
        const fieldApiName = event.target.name
        const value = event.detail.value

        this.updateSearchCriteria(fieldApiName,value);
    }

/// Values change
    handleFilterChange(event){
        const fieldApiName = event.detail.fieldApiName
        const value = event.detail.value

       this.updateSearchCriteria(fieldApiName,value);
    }


    /// clean the search criteria
    updateSearchCriteria(fieldApiName, value){
        // Clone existing criteria
        let criteria = {...this.searchCriteria}
        // Remove empty values
        const isEmpty =
            value === null ||
            value === undefined ||
            value === '' ||

            (
                Array.isArray(value) &&
                value.length === 0
            );

        if(isEmpty){

            delete criteria[fieldApiName];

        } else {

            criteria[fieldApiName] = value;
        }
        this.searchCriteria = criteria;
        this.dispatchEvent( new CustomEvent('searchfilter',{ detail: {
                                            searchCriteria: this.searchCriteria
                                                                     }}))
    }
}