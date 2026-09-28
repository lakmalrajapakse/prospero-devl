/*
 * Copyright Sirenum (c) 2021.
 */

import {LightningElement, api} from 'lwc';
import {NavigationMixin} from 'lightning/navigation';
import BASE_PATH from '@salesforce/community/basePath';

/**
 * Takes a raw URL that permits inclusion of the special ((CommunityURL)) placeholder or standard handlebar
 * parameters, such as {!CurrentUser.userName}, and generates a button or link that will navigate to that URL, after
 * processing and encoding, in the current window.
 */
export default class Navigate extends NavigationMixin(LightningElement) {
	/**
	 * Permit selection of the navigation style (link or button).
	 */
	@api
	get showAs() {
		return this._showAs;
	}

	set showAs(value) {
		this._showAs = value;

		this.button = (this._showAs === "button");
	}

	/**
	 * The required URL, supporting use of the special ((CommunityURL)) placeholder and standard handlebar
	 * parameters. E.g.:
	 *
	 * <pre>
	 * "https://sirenum.com/mobile/register/?url=((CommunityURL))&username={!CurrentUser.userName}".
	 * </pre>
	 *
	 * @type string
	 */
	@api
	get url() {
		return this._url;
	}

	set url(value) {
		this._url = value;

		this.calculateURL();
	}

	/**
	 * The link text or button label.
	 *
	 * @type string
	 */
	@api label;

	/**
	 * When rendering as a button, this defines the variant to use.
	 *
	 * @type string|undefined
	 */
	@api variant;

	/**
	 * The alignment for the component.
	 *
	 * @type string
	 */
	@api alignment;

	/**
	 * Internal storage for the specified API style.
	 *
	 * @private
	 * @type string
	 */
	_showAs;

	/**
	 * Internal storage for the specified API URL.
	 *
	 * @private
	 * @type string
	 */
	_url;

	/**
	 * Indicates whether to render as a button or not.
	 *
	 * @type boolean
	 */
	button;

	/**
	 * The URL to be rendered for navigation by the link or button.
	 */
	renderURL;

	/**
	 * Calculates the URL but only if the URL is known.
	 */
	calculateURL() {
		if (this._url) {
			const communityURL = window.location.origin + BASE_PATH;

			// Note that the "+" sign may be used in usernames. As such, and since encodeURI doesn't directly
			// handle it, these need to be manually replaced. The alternative would be to use encodeURIComponent,
			// but that means having to parse the URI to extract name/value pairs which is unnecessary effort here
			this.renderURL = encodeURI(
				this.url.replaceAll('((CommunityURL))', communityURL).replaceAll('+', '%2B'));
		}
	}

	/**
	 * The callback handler for a click of the button.
	 */
	navigate() {
		if (this.renderURL) {
			window.location = this.renderURL;
		}
	}
}