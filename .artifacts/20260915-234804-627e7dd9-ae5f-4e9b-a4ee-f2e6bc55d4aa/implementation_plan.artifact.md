# Restore Login Password Attempt Limit Feature

This plan outlines the steps to restore and fix the login password attempt limit feature, ensuring it follows the specified rules for attempts, lockouts, and messaging.

## User Review Required

> [!IMPORTANT]
> To distinguish between "User not found" and "Incorrect password", I will use `ApiService().checkUsername()` and `ApiService().checkEmail()`. This adds two extra API calls on failed login attempts. If the backend `login.php` could be updated to return this info directly, it would be more efficient.

## Proposed Changes

### [app_localizations.dart](file:///C:/xampp/htdocs/DITO-MUNA-master/lib/utils/app_localizations.dart)

- Add new localization keys for attempt remaining and lockout messages to match the requirements.
    - `err_incorrect_password_attempts`: "Incorrect password. {attempts} attempts remaining."
    - `err_account_locked_final`: "Too many incorrect password attempts. Your account is locked for 1 minute."

### [login_security_manager.dart](file:///C:/xampp/htdocs/DITO-MUNA-master/lib/utils/login_security_manager.dart)

- Add debug logs as required:
    - `[LOGIN] Incorrect password`
    - `[LOGIN] Failed attempts: X`
    - `[LOGIN] Remaining attempts: X`
    - `[LOGIN] Account locked until: <timestamp>`
    - `[LOGIN] Lock expired`
    - `[LOGIN] Successful login - attempts reset`
- Ensure `checkStatus` correctly handles and logs expired lockouts.

### [login_screen.dart](file:///C:/xampp/htdocs/DITO-MUNA-master/lib/screens/login_screen.dart)

- Update `_handleLogin` logic:
    - If login fails:
        - Check if the account exists using `ApiService().checkUsername()` and `ApiService().checkEmail()`.
        - If account exists:
            - Call `LoginSecurityManager.recordFailedAttempt()`.
            - Show message with remaining attempts or lockout message.
        - If account does not exist:
            - Show generic "Invalid username/email or password" message without attempts.
    - Add debug log for successful login.
- Update `_buildLockoutCard` to use the required message format.
- Call `_checkSecurityStatus()` in `_onUsernameChanged` to update UI immediately if a locked username is entered.

## Verification Plan

### Manual Verification
- **TEST 1**: Enter wrong password 4 times. Verify that it shows "1 attempt remaining" each time.
- **TEST 2**: Enter wrong password 5th time. Verify that the account locks for 1 minute and shows the "locked for 1 minute" message.
- **TEST 3**: Try the correct password during the 1-minute lock. Verify that login is still blocked.
- **TEST 4**: Wait for the 1-minute lock to expire. Verify that the counter resets and login is allowed.
- **TEST 5**: Enter correct password before reaching 5 failed attempts. Verify that login succeeds and the counter resets.
- **TEST 6**: Enter a non-existent username/email. Verify that it shows "Invalid username/email or password" without attempt count.
