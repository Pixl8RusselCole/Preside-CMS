/**
 * The forgotten password page type object is used to store any fields that are distinct to the system page type 'forgotten password'
 *
 * @isSystemPageType     true
 * @parentSystemPageType login
 * @pagetypeViewlet      login.forgottenPassword
 * @feature              websiteUsers
 *
 */
component extends="preside.system.base.SystemPresideObject" displayName="Page type: Forgotten password" {
    property name="loginId_not_found"                         type="string" dbtype="varchar" control="textArea";
    property name="invalid_reset_token"                       type="string" dbtype="varchar" control="textArea";
    property name="password_reset_instructions_sent"          type="string" dbtype="varchar" control="textArea";
    property name="newer_token_was_generated_error_message"   type="string" dbtype="varchar" control="textArea";
    property name="last_password_updated_error_message"       type="string" dbtype="varchar" control="textArea";
    property name="next_reset_password_allowed_error_message" type="string" dbtype="varchar" control="textArea";
}