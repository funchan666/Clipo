# Clipo Publication Notes — Internal, Do Not Publish as a Policy

The two English policy files are drafts tailored to the current iOS source. They are not an App Store approval guarantee or a jurisdiction-specific legal opinion. The operator must verify the commitments below against the actual backend, vendors, and launch markets before publication. Obtain qualified legal review for the jurisdictions in which the service will operate.

## Replace before publishing

The reformatted English copies are `Clipo Privacy Policy.docx` and `Clipo Terms of Use.docx`. Matching `.txt` files are available for plain-text website editors. They preserve the policy text, remove raw Markdown formatting from the delivered copy, and use these readable placeholders instead of the source Markdown tokens:

- `your-email@example.com`: replace every occurrence with your monitored contact email; keep the contact line first.
- `Your legal name or company name`: replace with the real operator name.
- `Month Day, Year`: replace with the effective date.

The `.md` files below remain the source drafts. Do not paste their raw Markdown into an editor that does not render Markdown.

- `[CONTACT_EMAIL]`: a working, monitored support and privacy email. Keep the bold contact line first on both pages. Make the address a mailto link in your website editor.
- `[OPERATOR_LEGAL_NAME]`: the actual individual or company legally operating Clipo, consistent with the service and developer identity.
- `[EFFECTIVE_DATE]`: the real date the policies take effect.

Publish each policy at a separate publicly accessible HTTPS URL, without login. Configure those URLs in the app and the relevant App Store Connect fields. The source configuration currently leaves `CLIPO_PRIVACY_URL` and `CLIPO_TERMS_URL` empty.

## Material checks before submission

1. **Account deletion:** the inspected app creates guest accounts but only exposes sign-out, not account deletion. An email in the policy is not a substitute for an in-app way to initiate deletion. Implement the deletion request and completion process, then update the policy with its exact in-app location. Do not claim a Delete Account button exists before it is implemented. [Apple account-deletion guidance](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).
2. **Subscription recovery:** the current purchase ledger cannot reconcile every transaction after a new installation or on another device without backend support. Complete and verify that recovery flow; terms cannot waive the requirement to make subscription access available across the user's devices. [Apple subscription guidelines](https://developer.apple.com/app-store/review/guidelines/#subscriptions).
3. **Backend facts:** confirm all data recipients, request/password logging, retention criteria, deletion execution, hosting countries, international-transfer safeguards, and provider contracts. The draft's statements about deletion and equivalent third-party protection are commitments the operator must actually honor. Frontend inspection does not establish backend compliance.
4. **Advertising:** the current project uses Google's demo advertising configuration. Review production consent, tracking behavior, vendor settings, and App Store privacy disclosures before release. Do not publish a claim that the app collects no data. [Google SDK data disclosures](https://developers.google.com/admob/ios/privacy/data-disclosure).
5. **Content and age:** verify rights to the supplied online content, the source service's permissions, the app's age rating, and the draft's minimum-age policy. If the feed contains user-generated content, assess and implement the applicable reporting, moderation, and blocking controls. An email address alone does not establish that those controls exist. [Apple safety and legal guidelines](https://developer.apple.com/app-store/review/guidelines/).
6. **Operational checks:** verify that the published links work in the app and App Store listing, support email receives mail, the backend is accessible during review, and subscription terms match the actual Apple products. These policies do not establish that login, purchase, restore, or ads have passed runtime testing.

## Drafting scope

The public drafts describe observed client behavior without inventing a cloud upload feature, email/password login, an in-app account deletion control, or a guaranteed refund outcome. Apple Standard EULA remains the software license; the Terms of Use add service rules. No application code or release configuration was changed as part of this document-writing task.
