import { LightningElement, api, track } from 'lwc';

export default class MultiSelectPicklist extends LightningElement {

    // ====================================
    // PUBLIC PROPERTIES
    // ====================================

    @api label
    @api options = []
    @api value = []
    @api placeholder
    @api fieldApiName
    @api helptext

    // ====================================
    // TRACKED VARIABLES
    // ====================================

    @track showDropdown = false
    @track filteredOptions = []

    // ====================================
    // LIFECYCLE
    // ====================================

    connectedCallback() {
        this.initializeOptions()
    }

    // ====================================
    // INITIALIZE OPTIONS
    // ====================================

    initializeOptions() {

        this.filteredOptions = this.options.map(option => {
            return {
                ...option,
                selected:
                    this.selectedValues.includes(option.value)
            };
        });
    }

 
    // ====================================
    // TOGGLE DROPDOWN
    // ====================================

    toggleDropdown(event) {

        event.preventDefault();
        event.stopPropagation();
        this.showDropdown = !this.showDropdown;
        this.initializeOptions();
    }

    // ====================================
    // HANDLE SELECT
    // ====================================

    handleSelect(event) {

        const selectedValue =
            event.target.dataset.value;

        const checked =
            event.target.checked;

        let values = [...this.selectedValues];

        if(checked){
            if(!values.includes(selectedValue)){
                values.push(selectedValue);
            }

        } else {
            values = values.filter(value => {
                return value !== selectedValue;
            });
        }

        this.value = values;

        this.initializeOptions();

        this.dispatchValueChange();
    }
    // ====================================
    // DISPATCH EVENT
    // ====================================

    dispatchValueChange() {

        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: {
                    fieldApiName:
                        this.fieldApiName,
                    value:
                        this.value
                }
            })
        );
    }

    /// getters

    // ====================================
    // SAFE VALUES
    // ====================================

    get selectedValues() {
        return this.value || []
    }

    // ====================================
    // DROPDOWN CLASS
    // ====================================

    get dropdownClass() {
        let classes =
            'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
        if(this.showDropdown){
            classes += ' slds-is-open';
        }
        return classes;
    }

    // ====================================
    // DISPLAY VALUE
    // ====================================

    get displayValue() {
        // No values selected
        if(this.selectedValues.length === 0){
            return this.placeholder || 'Select Values';
        }
        // Get selected labels
        const labels = this.options
            .filter(option =>
                this.selectedValues.includes(option.value)
            ).map(option => option.label);
        // 1 selected
        if(labels.length === 1){
            return labels[0];
        }
        // 2 selected
        if(labels.length === 2){

            return `${labels[0]}, ${labels[1]}`;
        }
        // More than 2
        return `${labels[0]}, ${labels[1]}...`;
    }

}