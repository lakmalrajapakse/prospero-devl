import { LightningElement, api, wire, track} from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi'
import CALL_LIST_OBJECT from '@salesforce/schema/TR1__Call_List__c'
import createCallListMembers from '@salesforce/apex/ClientContactSearchController.createCallListMembers'
export default class ClientSearchResults extends LightningElement {
    // Global Variable
    @api displayFields=[]
@api set searchResult(value){
        this.restoreSorting()
        this.records =
            [...(value || [])]
        this.applySorting()
        // New search results: start back on page 1 and clear stale selections
        this.currentPage = 1
        this.selectedIds = new Set()
    }

    // Component Variable
    sortingRestored = false
    callListName
    @track records = []
    defaultRecordTypeId =''
    showCallListModal = false
    isLoading = false

    // Pagination
    pageSize = 100
    currentPage = 1

    // Row selection, tracked by Id so it survives paging
    selectedIds = new Set()
    /// Wire method to get the recordType Id
    @wire(getObjectInfo, {
    objectApiName: CALL_LIST_OBJECT})
        objectInfo({data,error}){
            if(data){
                const recordTypes =data?.recordTypeInfos
            if(!recordTypes){
                return null
            }

            this.defaultRecordTypeId= Object.keys(recordTypes).find(id =>
                recordTypes[id].name  ==='Call List')
            }
            if(error){
                console.error('Error fetching recordType',error)
            }
        }
    
        /// Call list name
        handleNameChange(event){

            this.callListName = event.target.value;
        }
    /// Row selection
    /// The datatable only knows about rows on the current page, so we reconcile
    /// its selection against the current page's Ids and merge into the full set.
   handleRowSelection(event){
    const currentPageIds = new Set(this.paginatedRecords.map(row => row.Id))
    const updatedSelection = new Set(this.selectedIds)

    currentPageIds.forEach(id => updatedSelection.delete(id))
    event.detail.selectedRows.forEach(row => updatedSelection.add(row.Id))

    this.selectedIds = updatedSelection
    console.log('@@ Selected Ids: ',JSON.stringify(Array.from(this.selectedIds)))
    }

    /// Pagination handlers
    handlePreviousPage(){
        if(this.currentPage > 1){
            this.currentPage = this.currentPage - 1
        }
    }

    handleNextPage(){
        if(this.currentPage < this.totalPages){
            this.currentPage = this.currentPage + 1
        }
    }

    ///Click Handler
    callListHandler(event){
        this.showCallListModal = true
    }

    closeModal(){
        this.showCallListModal = false
    }

    handleSuccess(event){
        
        const callListId = event.detail.id;

        this.createdCallListId = callListId;

        this.addContactToCallList(callListId);
    }
    handleError(event){
        //this.showCallListModal = false
        this.dispatchEvent( new CustomEvent('calllist',{ detail: {
                                            title: 'Error',
                                            message: event.detail.message ? event.detail.message: 'Issue occured while creating callList, Please contact System Admin.',
                                            variant: 'error'
                                                                     }}))
    }

    async addContactToCallList(callListId){
            try{
                this.isLoading= true
            await createCallListMembers({callListId: callListId, contactIds: Array.from(this.selectedIds)})
            this.dispatchEvent( new CustomEvent('calllist',
                                                        {
                                                            detail:{
                                                                title:'Success',
                                                                message:
                                                                    `Call List {0} created successfully. `,
                                                                variant:'success',
                                                                callListId:
                                                                    callListId,
                                                                callListName:
                                                                    this.callListName
                                                            }
                                                        } ))
        }catch(error){
            this.dispatchEvent( new CustomEvent('calllist',{ detail: {
                                            title: 'Error',
                                            message: error.body.message ? error.body.message: 'Issue occured while creating callList, Please contact System Admin.',
                                            variant: 'error'
                                                                     }}))
        }finally{
            this.isLoading = false
            this.showCallListModal = false
        }
    }
    
    // Handle Sorting
    defaultSortDirection = 'asc';
    sortDirection = 'asc';
    sortedBy;

    onHandleSort(event){
        const { fieldName: sortedBy, sortDirection} = event.detail

        this.sortedBy = sortedBy
        this.sortDirection = sortDirection
        this.applySorting()

        localStorage.setItem( 'clientSearchSort', JSON.stringify({ sortedBy: this.sortedBy, sortDirection: this.sortDirection }) )
    }

    sortBy(field, reverse){

        return (a, b) => {let valueA = a[field]
            let valueB =
                b[field]

            // Handle nulls
            valueA = valueA == null ? '' : valueA

            valueB = valueB == null  ? ''  : valueB
            // Distance sorting
            if(field === 'Distance'){

                valueA =  Number(valueA)

                valueB = Number(valueB)
            }

            return reverse *
                ((valueA > valueB) -
                (valueB > valueA))
        }
    }

    /// Colum Sorting helper
    applySorting(){
        if(!this.sortedBy || !this.records?.length){
                return
            }

            const cloneData = [...this.records]
            cloneData.sort(this.sortBy( this.sortedBy,this.sortDirection === 'asc'
                        ? 1
                        : -1
                ) )
            this.records =cloneData
    }

    restoreSorting(){
        if(this.sortingRestored){
            return
        }
        const savedSort = localStorage.getItem(  'clientSearchSort')
        if(savedSort){
            const sortConfig = JSON.parse(savedSort)
            this.sortedBy = sortConfig.sortedBy
            this.sortDirection = sortConfig.sortDirection
        }

        this.sortingRestored = true
    }
    
    ///Getters
    get columns(){

        let columns = []

        this.displayFields.forEach(field => {
            let column = { label: field.label, fieldName: field.fieldName,sortable: true}
            // Email
            if(field.fieldName === 'Email'){
                column.type = 'email'
            }

            // Phone
            else if(field.fieldName === 'Phone'){
                column.type = 'phone'
            }

            // Website
            else if( field.fieldName === 'Website' ||field.fieldName === 'Website__c'){
                column.type = 'url'
                column.typeAttributes = {
                    label: {
                        fieldName: field.fieldName
                    },
                    target: '_blank'
                }
            }

            // Distance
            else if(field.fieldName === 'Distance'){
                column.type = 'number'
                column.typeAttributes = {
                    minimumFractionDigits: 1,
                    maximumFractionDigits: 1
                }
                column.cellAttributes = {
                    class: 'slds-text-color_success slds-text-title_bold'
                }
            }
            else{

                column.type = 'text'
            }

            columns.push(column)
        })

        return columns
    }

    get disableCallList(){
        return this.selectedIds.size === 0
    }

    get searchResult(){
        return this.records
    }

    get tableStyle(){
        const rowHeight = 40
        const headerHeight = 50
        const visibleRows = Math.min(this.pageSize, this.records?.length || 0)
        let height = visibleRows * rowHeight + headerHeight
        height = Math.min(height, 700)
        return `height:${height}px`
    }

    /// Pagination getters
    get totalPages(){
        return Math.max(1, Math.ceil((this.records?.length || 0) / this.pageSize))
    }

    get paginatedRecords(){
        const start = (this.currentPage - 1) * this.pageSize
        return this.records.slice(start, start + this.pageSize)
    }

    get selectedRowsForPage(){
        const currentPageIds = this.paginatedRecords.map(row => row.Id)
        return currentPageIds.filter(id => this.selectedIds.has(id))
    }

    get isFirstPage(){
        return this.currentPage <= 1
    }

    get isLastPage(){
        return this.currentPage >= this.totalPages
    }

    get pageRangeLabel(){
        const total = this.records?.length || 0
        if(total === 0){
            return 'No records found'
        }
        const start = (this.currentPage - 1) * this.pageSize + 1
        const end = Math.min(this.currentPage * this.pageSize, total)
        return `${start}-${end} of ${total}`
    }
}