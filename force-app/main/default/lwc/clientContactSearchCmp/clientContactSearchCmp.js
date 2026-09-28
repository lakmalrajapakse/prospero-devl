import { LightningElement,wire, api, track } from 'lwc';
import USER_ID from "@salesforce/user/Id";
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import getConfig from '@salesforce/apex/ClientContactSearchController.getConfig'
import getDynamicFilters from '@salesforce/apex/ClientContactSearchController.getDynamicFilters'
import getLatLong from '@salesforce/apex/ClientContactSearchController.searchPostCode'
import getSearchedContact from '@salesforce/apex/ClientContactSearchController.getSearchedContact'
const FIELDS = ['User.Profile.Name']
export default class ClientContactSearchCmp extends LightningElement {
    radius
    countryCodes=[]
    fieldSetName=''
    selectedCountryCode
    isLoading = true
    profileName
    selectedBrand
    postalCode=''
    dynamicFilters
    defaultWhereClause=''
    additionalFilters={}

    searchResult = []
    displayFields = []

    showEmptyState = false

    // Wire methods
    ///1 to get the basic configuration like, Country Code and radius
    @wire(getConfig)
    wiredConfig({data, error}){
        if(data){
            this.radius = data.defaultRadius
            this.countryCodes = data.countryCodes
            this.selectedCountryCode = data.defaultCountryCode
            this.fieldSetName = data.fieldSetName
            this.defaultWhereClause = data.defaultWhereClause
        }
        if(error){
            console.error('Error fetching config:', error)
            const message = error?.body?.message || error?.message || 'Unexpected error occurred'
            this.showMessage('Error', message, 'error')
            this.isLoading = false
        }
    }

    ///2 Wire method to get the current user's Profile
   @wire(getRecord, { recordId: USER_ID, fields: FIELDS})
    wiredUser({ error, data }) {
        if(data){
            this.profileName =data.fields.Profile.displayValue || data.fields.Profile.value.fields.Name.value
            switch(this.profileName){
                case 'Prospero Health & Social Care User': this.selectedBrand = 'Health & Social Care'
                    break

                case 'Prospero Teaching User': this.selectedBrand = 'Teaching'
                    break

                case 'Prospero Integrated': this.selectedBrand = 'Integrated'
                    break
                default: this.selectedBrand = 'All'
            }
            console.log( '@@@@ Selected Brand:', this.selectedBrand)

        }else if(error){
            console.error(error)
            const message = error?.body?.message || error?.message || 'Unexpected error occurred'
            this.showMessage('Error', message, 'error')
        }
    }

    ///3 to get the dynamic filter metadata
   @wire(getDynamicFilters,{brand: '$selectedBrand'})
    wiredFilters({ data, error }) {
        if(data){
            this.isLoading = true
            // Enrich metadata for UI rendering
            this.dynamicFilters = data.map(filter => {
                let cssClass ='slds-col slds-p-around_x-small ';

         switch(filter.uiType){

            case 'MultiPicklist':
                cssClass +=
                    'slds-size_1-of-4';
                break;

            case 'Picklist':
                cssClass +=
                    'slds-size_1-of-1 slds-medium-size_1-of-4';
                break;

            case 'Lookup':
                cssClass +=
                    'slds-size_1-of-1 slds-medium-size_1-of-4'

                break

            default:
                cssClass +=
                    'slds-size_1-of-1 slds-medium-size_1-of-4';
        }

        return {

            ...filter,

            cssClass,

            isText:
                filter.uiType === 'Text',

            isNumber:
                filter.uiType === 'Number',

            isPicklist:
                filter.uiType === 'Picklist',

            isMultiPicklist:
                filter.uiType === 'MultiPicklist',
            isLookup:
                filter.uiType ==='Lookup'
            
        }
    })
        this.isLoading = false
        }

        if(error){
            console.error( 'Error fetching dynamic filters:',error);
            const message = error?.body?.message || error?.message || 'Unexpected error occurred'
            this.showMessage('Error', message, 'error')
             this.isLoading = false
        }
    }


    /// Input Handler
    /// On change
    handleChange(event){
        const { name, value } = event.target;
        this[name] = value
    }

    /// handle Additional filter from child
    handleAdditionalFilters(event){
        this.additionalFilters = event.detail.searchCriteria
        console.log( 'Search Criteria from child', JSON.stringify(this.additionalFilters) )
    }

    // Search Handler
  async searchHandler(){
    try{
        if(!this.radius || !this.selectedCountryCode || !this.postalCode){
            this.showMessage('Error','Please enter the (*)required fields to perform search','error')
            return
        }
        this.isLoading = true
        this.showEmptyState = false
        /// Call the method to get Lat/long and fields to display
        const result = await getLatLong({fieldset : this.fieldSetName,
                                         country: this.selectedCountryCode,
                                         postCode: this.postalCode
                                                                })
        // Validation error
        if(!result.success){
            this.showMessage( 'Error', result.message,'error')
            this.isLoading = false
            return
        }
        // Success
        this.displayFields = result.fields
        const fieldNames =this.displayFields.map(field => {return field.fieldName})
        console.log('Latitude', result.latitude)
        console.log('Longitude', result.longitude)

        /// Call the method to get the record within this radius and followed by additional filter and default where clause
        const contacts = await getSearchedContact({
                                                    displayFields: fieldNames,
                                                    additionalFilters: this.additionalFilters,
                                                    whereClause: this.defaultWhereClause,
                                                    radius: this.radius,
                                                    lat: result.latitude,
                                                    lon: result.longitude
                                                        })
        console.log('Client Contacts: ', JSON.stringify(contacts))
        if(contacts && contacts.length > 0){
            this.searchResult = contacts
        }else{
            this.showEmptyState = true
            this.searchResult =[]
        }
        
        
    }catch(error){
            console.error('Search Error', error)

        let message ='Unexpected error occurred'
        // Apex handled exception
        if( error.body && error.body.message){
            message =  error.body.message
        }
        this.showEmptyState = true
        this.searchResult =[]
        this.showMessage( 'Error',  message, 'error')
    }finally{
        this.isLoading = false
    }
        
    }

    /// Child method: 
    callListhandler(event){

            const {  title, message, variant, callListId, callListName } = event.detail
    
        if(callListId){
            this.dispatchEvent(
                new ShowToastEvent({
                    title: title,
                    message: message,
                    variant: variant,
                    messageData: [
                        {
                            url: '/' + callListId,
                            label: callListName
                        }
                    ]
                })
            );

        }else{
            this.showMessage( title, message, variant );
        }
}

    // Getter
    get showResults(){
        return this.searchResult && this.searchResult.length >0
    }
    showMessage(title, message, variant){
        const evt = new ShowToastEvent({
            title,message,variant
        })
        this.dispatchEvent(evt);
    }

}