import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'legal_content.dart';

enum AppLanguage { en, fil, bis }

class AppLocalizations {
  static const String _storageKey = 'app_language';
  static final ValueNotifier<AppLanguage> currentLanguage = ValueNotifier(AppLanguage.en);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? langCode = prefs.getString(_storageKey);
    if (langCode != null) {
      if (langCode == 'fil') currentLanguage.value = AppLanguage.fil;
      else if (langCode == 'bis') currentLanguage.value = AppLanguage.bis;
      else currentLanguage.value = AppLanguage.en;
    }
  }

  static Future<void> setLanguage(AppLanguage lang) async {
    currentLanguage.value = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, lang.name);
  }

  static String get(String key) {
    switch (currentLanguage.value) {
      case AppLanguage.fil:
        return _filipino[key] ?? _english[key] ?? key;
      case AppLanguage.bis:
        return _bisaya[key] ?? _english[key] ?? key;
      default:
        return _english[key] ?? key;
    }
  }

  static String getTerms() {
    switch (currentLanguage.value) {
      case AppLanguage.fil:
        return LegalContent.termsAndConditionsFil;
      case AppLanguage.bis:
        return LegalContent.termsAndConditionsBis;
      default:
        return LegalContent.termsAndConditionsEn;
    }
  }

  static String getPrivacy() {
    switch (currentLanguage.value) {
      case AppLanguage.fil:
        return LegalContent.privacyPolicyFil;
      case AppLanguage.bis:
        return LegalContent.privacyPolicyBis;
      default:
        return LegalContent.privacyPolicyEn;
    }
  }

  static final Map<String, String> _english = {
    // Login
    'welcome_back': 'Welcome Back',
    'sign_in_continue': 'Sign in to continue',
    'username_email': 'Username / Email',
    'enter_credentials': 'Enter your credentials',
    'password': 'Password',
    'enter_password': 'Enter your password',
    'forgot_password': 'Forgot Password?',
    'sign_in': 'Sign In',
    'dont_have_account': "Don't have an account? ",
    'create_account': 'Create Account',
    'garbage_tracker': 'Garbage Tracker',

    // Forgot Password
    'verification': 'Verification',
    'account_recovery': 'Account Recovery',
    'enter_token': 'Enter Token',
    'new_password': 'New Password',
    'step_1_verify': 'Step 1: Verify Identity',
    'step_2_token': 'Step 2: Enter Token',
    'step_3_secure': 'Step 3: Secure Account',
    'email_address': 'Email Address',
    'enter_reg_email': 'Enter your registered email',
    'send_verification': 'Send Verification',
    'verification_token': 'Verification Token',
    'expires_in': 'Expires in',
    'code_sent_to': 'Code sent to',
    'didnt_receive_token': "Didn't receive a token?",
    'resend_token': 'Resend Token',
    'confirm_password': 'Confirm Password',
    'confirm_your_password': 'Confirm your password',
    'reset_password': 'Reset Password',
    'request_new_code': 'Request a new code',

    // Create Account Choice
    'select_type': 'Select your account type to continue',
    'resident': 'Resident',
    'driver': 'Driver',
    'track_trucks': 'Track trucks and file complaints',
    'manage_routes': 'Manage routes and track collections',

    // Registration
    'registration_form': 'Registration Form',
    'credentials': 'Account Credentials',
    'personal_details': 'Personal Details',
    'work_info': 'Work Information',
    'username': 'Username',
    'email': 'Email Address',
    'full_name': 'Full Name',
    'contact_number': 'Contact Number',
    'purok': 'Purok',
    'complete_address': 'Complete Address',
    'license_number': 'License Number',
    'preferred_truck': 'Preferred Truck (Optional)',
    'agree_terms': 'I have read and agree to the ',
    'terms_conditions': 'Terms & Conditions',
    'and': ' & ',
    'privacy_policy': 'Privacy Policy',
    'submit_registration': 'Submit Registration',
    'register_as_driver': 'Register as Driver',
    'back_to_login': 'Back to Login',
    'select_location': 'Select your location',
    'select_purok': 'Select Purok',
    'select_language': 'Select Language',
    'close': 'Close',
    'welcome_name': 'Welcome Back, {name}!',
    'complete_form_correctly': 'Please complete the form correctly',
    'email_not_found': 'Email not found in our records',
    'please_wait_opening': 'Please wait, opening the app...',
    'splash_loading_portal': 'Please wait, opening the portal...',
    'resident_desc': 'Join our waste management community',
    'driver_desc': 'Official Service Partner Registration',
    'purok_selection_desc': 'Please select the Purok where your residence is located.',
    'language_selection_desc': 'Select your preferred language for the application.',

    // Loading & Status
    'verifying_email': 'Verifying Email...',
    'checking_token': 'Checking Token...',
    'updating_password': 'Updating Password...',
    'confirming_credentials': 'Confirming Credentials...',
    'processing_registration': 'Processing Registration...',
    'processing': 'Processing...',

    // 2FA & Lockout
    'two_step_verification': 'Two-Step Verification',
    'otp_email_msg': 'Enter the 6-digit code sent to your email:\n{email}',
    'verify_login': 'Verify & Login',
    'resend_code': 'Resend Code',
    'enter_otp_code': 'Please enter the 6-digit code',
    'verification_successful': 'Verification Successful!',
    'err_otp_invalid': 'Invalid verification code',
    'sending_code': 'Sending new code...',
    'err_resend_failed': 'Failed to resend code',
    'security_lockout': 'Security Lockout',
    'err_lockout_msg': 'Login is temporarily disabled due to multiple failed attempts.',
    'reset_password_link': 'Reset your password',
    'reg_success': 'Registration successful!',
    'reg_failed': 'Registration failed',
    'new_reg_notif': '{name} has registered as a resident.',
    'new_driver_reg_notif': '{name} has joined as a driver.',
    'new_reg_title': 'New Registration',
    'new_driver_reg_title': 'New Driver Registered',

    // Errors (Formal)
    'err_username_email': 'Please enter your username or email to continue.',
    'err_username_reg': 'Username is required for registration.',
    'err_email_req_reg': 'Email address is required for registration.',
    'err_password_reg': 'Password is required for registration.',
    'err_password_req': 'Please enter your password to proceed.',
    'err_auth_failed': 'Invalid username/email or password',
    'err_connection': 'Server connection error. Please ensure the backend services are operational.',
    'err_email_reg': 'Please enter your registered email address.',
    'err_email_format': 'Please enter a valid email format.',
    'err_otp_req': 'Please enter the verification code sent to your email.',
    'err_otp_len': 'The verification code must be exactly 6 digits.',
    'err_otp_expired': 'The verification code has expired. Please request a new code.',
    'err_pass_new': 'Please enter a new secure password.',
    'err_pass_len': 'Password must be at least 6 characters long.',
    'err_pass_complex': 'Include an uppercase letter, lowercase letter, a number, and a special character.',
    'err_pass_match': 'Passwords do not match. Please ensure both fields are identical.',
    'err_username_taken': 'This username is already taken. Please choose another.',
    'err_email_taken': 'This email is already registered. Please use another.',
    'err_phone_taken': 'This contact number is already registered. Please use another.',
    'err_name_req': 'Your full name is required for registration.',
    'err_name_format': 'Please use letters and spaces only for your name.',
    'err_phone_req': 'A valid contact number is required for verification.',
    'err_phone_format': 'Please enter a valid PH contact number (e.g., 09xxxxxxxxx).',
    'err_license_req': 'A valid driver\'s license number is required.',
    'err_license_format': 'Invalid license format detected.',
    'err_purok_req': 'Please select your residential Purok.',
    'err_terms_req': 'Please read and accept the Terms & Conditions.',
    'err_general': 'Please correct the highlighted errors to proceed.',
    'err_network': 'A network error occurred. Please check your internet connection and try again.',
    'err_incorrect_password_attempts': 'Incorrect password. {attempts} attempts remaining.',
    'err_account_locked_final': 'Too many incorrect password attempts. Your account is locked for 1 minute.',

    // Permissions & Common
    'permissions_required': 'Permissions Required',
    'permissions_desc': 'To use the Garbage Tracker, you must enable Location Services and allow Notifications. This ensures real-time tracking and collection alerts work correctly.',
    'open_settings': 'Open Settings',
    'go_back': 'Go Back',
    'retry_connection': 'Retry Connection',
    'no_internet': 'No Internet Connection',
    'brgy_footer': '© 2026 Brgy. Balintawak Lipa City',
    'all_rights_reserved': 'All rights reserved',
  };

  static final Map<String, String> _filipino = {
    // Login
    'welcome_back': 'Maligayang Pagbabalik',
    'sign_in_continue': 'Mag-login para magpatuloy',
    'username_email': 'Username / Email',
    'enter_credentials': 'Ipasok ang iyong credentials',
    'password': 'Password',
    'enter_password': 'Ipasok ang iyong password',
    'forgot_password': 'Nakalimutan ang Password?',
    'sign_in': 'Mag-Sign In',
    'dont_have_account': 'Wala pang account? ',
    'create_account': 'Gumawa ng Account',
    'garbage_tracker': 'Tagasubaybay ng Basura',

    // Forgot Password
    'verification': 'Pagpapatunay',
    'account_recovery': 'Pagbawi ng Account',
    'enter_token': 'Ipasok ang Token',
    'new_password': 'Bagong Password',
    'step_1_verify': 'Hakbang 1: Patunayan ang Pagkakakilanlan',
    'step_2_token': 'Hakbang 2: Ipasok ang Token',
    'step_3_secure': 'Hakbang 3: I-secure ang Account',
    'email_address': 'Email Address',
    'enter_reg_email': 'Ipasok ang iyong rehistradong email',
    'send_verification': 'Ipadala ang Pagpapatunay',
    'verification_token': 'Verification Token',
    'expires_in': 'Mag-e-expire sa loob ng',
    'code_sent_to': 'Code na ipinadala sa',
    'didnt_receive_token': 'Hindi nakatanggap ng token?',
    'resend_token': 'Ipadala Muli ang Token',
    'confirm_password': 'Kumpirmahin ang Password',
    'confirm_your_password': 'Kumpirmahin ang iyong password',
    'reset_password': 'I-reset ang Password',
    'request_new_code': 'Humiling ng bagong code',

    // Create Account Choice
    'select_type': 'Pumili ng uri ng account para magpatuloy',
    'resident': 'Residente',
    'driver': 'Drayber',
    'track_trucks': 'Subaybayan ang mga trak at maghain ng reklamo',
    'manage_routes': 'Pamahalaan ang mga ruta at koleksyon',

    // Registration
    'registration_form': 'Form ng Rehistrasyon',
    'credentials': 'Mga Detalye ng Account',
    'personal_details': 'Personal na Detalye',
    'work_info': 'Impormasyon sa Trabaho',
    'username': 'Username',
    'email': 'Email Address',
    'full_name': 'Buong Pangalan',
    'contact_number': 'Numero ng Telepono',
    'purok': 'Purok',
    'complete_address': 'Kumpletong Address',
    'license_number': 'Numero ng Lisensya',
    'preferred_truck': 'Gustong Trak (Opsyonal)',
    'agree_terms': 'Nabasa ko na at sumasang-ayon sa ',
    'terms_conditions': 'Mga Tuntunin & Kondisyon',
    'and': ' & ',
    'privacy_policy': 'Patakaran sa Pribasidad',
    'submit_registration': 'Isumite ang Rehistrasyon',
    'register_as_driver': 'Magparehistro bilang Drayber',
    'back_to_login': 'Bumalik sa Login',
    'select_location': 'Piliin ang iyong lokasyon',
    'select_purok': 'Pumili ng Purok',
    'select_language': 'Pumili ng Wika',
    'close': 'Isara',
    'welcome_name': 'Maligayang Pagbabalik, {name}!',
    'complete_form_correctly': 'Pakikumpleto ang form nang tama',
    'email_not_found': 'Hindi nahanap ang email sa aming record',
    'please_wait_opening': 'Pakihintay, binubuksan ang app...',
    'splash_loading_portal': 'Pakihintay, binubuksan ang portal...',
    'resident_desc': 'Sumali sa aming komunidad ng waste management',
    'driver_desc': 'Opisyal na Rehistrasyon ng Service Partner',
    'purok_selection_desc': 'Pakipili ang Purok kung saan matatagpuan ang iyong tirahan.',
    'language_selection_desc': 'Piliin ang iyong gustong wika para sa aplikasyon.',

    // Loading & Status
    'verifying_email': 'Sini-verify ang Email...',
    'checking_token': 'Sini-verify ang Token...',
    'updating_password': 'Ina-update ang Password...',
    'confirming_credentials': 'Kinukumpirma ang Credentials...',
    'processing_registration': 'Pinoproseso ang Rehistrasyon...',
    'processing': 'Pinoproseso...',

    // 2FA & Lockout
    'two_step_verification': 'Two-Step na Pagpapatunay',
    'otp_email_msg': 'Ipasok ang 6-digit code na ipinadala sa iyong email:\n{email}',
    'verify_login': 'I-verify at Mag-login',
    'resend_code': 'Ipadala Muli ang Code',
    'enter_otp_code': 'Pakipasok ang 6-digit code',
    'verification_successful': 'Matagumpay ang Pagpapatunay!',
    'err_otp_invalid': 'Maling verification code',
    'sending_code': 'Ipinapadala ang bagong code...',
    'err_resend_failed': 'Nabigong ipadala muli ang code',
    'security_lockout': 'Security Lockout',
    'err_lockout_msg': 'Pansamantalang hindi pinagana ang login dahil sa maraming maling pagsubok.',
    'reset_password_link': 'I-reset ang iyong password',
    'reg_success': 'Matagumpay ang rehistrasyon!',
    'reg_failed': 'Nabigo ang rehistrasyon',
    'new_reg_notif': 'Si {name} ay nagparehistro bilang residente.',
    'new_driver_reg_notif': 'Si {name} ay sumali bilang drayber.',
    'new_reg_title': 'Bagong Rehistrasyon',
    'new_driver_reg_title': 'Bagong Drayber na Rehistrado',

    // Errors
    'err_username_email': 'Pakipasok ang iyong username o email para magpatuloy.',
    'err_username_reg': 'Kailangan ang username para sa rehistrasyon.',
    'err_email_req_reg': 'Kailangan ang email para sa rehistrasyon.',
    'err_password_reg': 'Kailangan ang password para sa rehistrasyon.',
    'err_password_req': 'Pakipasok ang iyong password para magpatuloy.',
    'err_auth_failed': 'Maling username/email o password',
    'err_connection': 'Error sa koneksyon ng server. Pakisuri kung operational ang backend.',
    'err_email_reg': 'Pakipasok ang iyong rehistradong email address.',
    'err_email_format': 'Pakipasok ang wastong format ng email.',
    'err_otp_req': 'Pakipasok ang verification code na ipinadala sa iyong email.',
    'err_otp_len': 'Ang verification code ay dapat na eksaktong 6 na digit.',
    'err_otp_expired': 'Nag-expire na ang verification code. Pakihiling ng bagong code.',
    'err_pass_new': 'Pakipasok ang bagong secure na password.',
    'err_pass_len': 'Ang password ay dapat na hindi bababa sa 6 na karakter.',
    'err_pass_complex': 'Isama ang uppercase, lowercase, numero, at espesyal na karakter.',
    'err_pass_match': 'Hindi magkatugma ang mga password. Siguraduhing magkapareho ang dalawa.',
    'err_username_taken': 'Ang username na ito ay nakuha na. Pumili ng iba.',
    'err_email_taken': 'Ang email na ito ay rehistrado na. Gumamit ng iba.',
    'err_phone_taken': 'Ang numerong ito ay gamit na. Gumamit ng iba.',
    'err_name_req': 'Ang iyong buong pangalan ay kailangan para sa rehistrasyon.',
    'err_name_format': 'Gumamit lamang ng mga titik at espasyo para sa iyong pangalan.',
    'err_phone_req': 'Kailangan ng wastong numero para sa pagpapatunay.',
    'err_phone_format': 'Pakipasok ang wastong PH contact number (hal. 09xxxxxxxxx).',
    'err_license_req': 'Kailangan ng wastong numero ng lisensya.',
    'err_license_format': 'Maling format ng lisensya ang natukoy.',
    'err_purok_req': 'Pakipili ang iyong tinitirahang Purok.',
    'err_terms_req': 'Pakibasa at tanggapin ang Mga Tuntunin at Kundisyon.',
    'err_general': 'Pakitama ang mga highlight na error para magpatuloy.',
    'err_network': 'Nagkaroon ng network error. Pakisubukang muli mamaya.',
    'err_incorrect_password_attempts': 'Maling password. {attempts} na pagsubok ang natitira.',
    'err_account_locked_final': 'Masyadong maraming maling pagsubok. Ang iyong account ay naka-lock sa loob ng 1 minuto.',

    // Permissions & Common
    'permissions_required': 'Kailangan ng mga Permisyon',
    'permissions_desc': 'Upang magamit ang Garbage Tracker, dapat mong paganahin ang Location Services at payagan ang Notifications. Tinitiyak nito na ang real-time tracking at mga alerto sa koleksyon ay gagana nang tama.',
    'open_settings': 'Buksan ang Settings',
    'go_back': 'Bumalik',
    'retry_connection': 'Subukan Muli ang Koneksyon',
    'no_internet': 'Walang Koneksyon sa Internet',
    'brgy_footer': '© 2026 Brgy. Balintawak Lipa City',
    'all_rights_reserved': 'Lahat ng karapatan ay reserbado',
  };

  static final Map<String, String> _bisaya = {
    // Login
    'welcome_back': 'Maayong Pagbalik',
    'sign_in_continue': 'Mag-login para mopadayon',
    'username_email': 'Username / Email',
    'enter_credentials': 'Isulod ang imong mga detalye',
    'password': 'Password',
    'enter_password': 'Isulod ang imong password',
    'forgot_password': 'Nakalimot sa Password?',
    'sign_in': 'Mag-Sign In',
    'dont_have_account': 'Wala pay account? ',
    'create_account': 'Paghimo og Account',
    'garbage_tracker': 'Tigsubay sa Basura',

    // Forgot Password
    'verification': 'Pagmatuod',
    'account_recovery': 'Pagbawi sa Account',
    'enter_token': 'Isulod ang Token',
    'new_password': 'Bag-ong Password',
    'step_1_verify': 'Lakang 1: Pamatud-i ang Pagkatawo',
    'step_2_token': 'Lakang 2: Isulod ang Token',
    'step_3_secure': 'Lakang 3: I-secure ang Account',
    'email_address': 'Email Address',
    'enter_reg_email': 'Isulod ang imong rehistradong email',
    'send_verification': 'Ipadala ang Pagmatuod',
    'verification_token': 'Verification Token',
    'expires_in': 'Mapas na sa sulod sa',
    'code_sent_to': 'Ang code gipadala sa',
    'didnt_receive_token': 'Wala nakadawat og token?',
    'resend_token': 'Ipadala Pag-usab ang Token',
    'confirm_password': 'Kumpirmaha ang Password',
    'confirm_your_password': 'Kumpirmaha ang imong password',
    'reset_password': 'I-reset ang Password',
    'request_new_code': 'Pangayo og bag-ong code',

    // Create Account Choice
    'select_type': 'Pilia ang klase sa account para mopadayon',
    'resident': 'Residente',
    'driver': 'Drayber',
    'track_trucks': 'Subaya ang mga trak ug pagsumite og reklamo',
    'manage_routes': 'Dumala ang mga ruta ug koleksyon',

    // Registration
    'registration_form': 'Porma sa Rehistrasyon',
    'credentials': 'Mga Detalye sa Account',
    'personal_details': 'Personal nga Detalye',
    'work_info': 'Impormasyon sa Trabaho',
    'username': 'Username',
    'email': 'Email Address',
    'full_name': 'Tibuok Pangalan',
    'contact_number': 'Numero sa Telepono',
    'purok': 'Purok',
    'complete_address': 'Kompletong Address',
    'license_number': 'Numero sa Lisensya',
    'preferred_truck': 'Gipili nga Trak (Opsyonal)',
    'agree_terms': 'Nabasa nako ug miuyon sa ',
    'terms_conditions': 'Mga Termino & Kondisyon',
    'and': ' & ',
    'privacy_policy': 'Polisiya sa Pribasidad',
    'submit_registration': 'Isumite ang Rehistrasyon',
    'register_as_driver': 'Magparehistro isip Drayber',
    'back_to_login': 'Balik sa Login',
    'select_location': 'Pilia ang imong lokasyon',
    'select_purok': 'Pilia ang Purok',
    'select_language': 'Pilia ang Pinulongan',
    'close': 'Isira',
    'welcome_name': 'Maayong Pagbalik, {name}!',
    'complete_form_correctly': 'Palihug kompletoha ang porma sa husto',
    'email_not_found': 'Wala makit-i ang email sa among mga record',
    'please_wait_opening': 'Palihug hulata, giablihan ang app...',
    'splash_loading_portal': 'Palihug hulata, giablihan ang portal...',
    'resident_desc': 'Apil sa among waste management nga komunidad',
    'driver_desc': 'Opisyal nga Rehistrasyon sa Service Partner',
    'purok_selection_desc': 'Palihug pilia ang Purok kung asa nahimutang ang imong balay.',
    'language_selection_desc': 'Pilia ang imong gusto nga pinulongan para sa aplikasyon.',

    // Loading & Status
    'verifying_email': 'Sini-verify ang Email...',
    'checking_token': 'Sini-verify ang Token...',
    'updating_password': 'Ina-update ang Password...',
    'confirming_credentials': 'Kinukumpirma ang Credentials...',
    'processing_registration': 'Pinoproseso ang Rehistrasyon...',
    'processing': 'Pinoproseso...',

    // 2FA & Lockout
    'two_step_verification': 'Two-Step nga Pagmatuod',
    'otp_email_msg': 'Isulod ang 6-digit code nga gipadala sa iyong email:\n{email}',
    'verify_login': 'I-verify at Mag-login',
    'resend_code': 'Ipadala Pag-usab ang Code',
    'enter_otp_code': 'Palihug isulod ang 6-digit code',
    'verification_successful': 'Malamposon ang Pagmatuod!',
    'err_otp_invalid': 'Sayop nga verification code',
    'sending_code': 'Gipadala ang bag-ong code...',
    'err_resend_failed': 'Napakyas sa pagpadala pag-usab sa code',
    'security_lockout': 'Security Lockout',
    'err_lockout_msg': 'Temporaryong gi-disable ang login tungod sa daghang sayop nga pagsulay.',
    'reset_password_link': 'I-reset ang imong password',
    'reg_success': 'Malamposon ang rehistrasyon!',
    'reg_failed': 'Napakyas ang rehistrasyon',
    'new_reg_notif': 'Si {name} nagparehistro isip residente.',
    'new_driver_reg_notif': 'Si {name} miapil isip drayber.',
    'new_reg_title': 'Bag-ong Rehistrasyon',
    'new_driver_reg_title': 'Bag-ong Drayber nga Rehistrado',

    // Errors
    'err_username_email': 'Palihug isulod ang imong username o email para mopadayon.',
    'err_username_reg': 'Gikinahanglan ang username para sa rehistrasyon.',
    'err_email_req_reg': 'Gikinahanglan ang email para sa rehistrasyon.',
    'err_password_reg': 'Gikinahanglan ang password para sa rehistrasyon.',
    'err_password_req': 'Palihug isulod ang imong password para mopadayon.',
    'err_auth_failed': 'Sayop nga username/email o password',
    'err_connection': 'Error sa koneksyon sa server. Siguraduhon nga operational ang backend.',
    'err_email_reg': 'Palihug isulod ang imong rehistradong email address.',
    'err_email_format': 'Palihug isulod ang husto nga format sa email.',
    'err_otp_req': 'Palihug isulod ang verification code nga gipadala sa imong email.',
    'err_otp_len': 'Ang verification code kinahanglan eksaktong 6 ka digit.',
    'err_otp_expired': 'Napapas na ang verification code. Palihug pangayo og bag-o.',
    'err_pass_new': 'Palihug isulod ang bag-ong secure nga password.',
    'err_pass_len': 'Ang password kinahanglan dili moubos sa 6 ka karakter.',
    'err_pass_complex': 'Iapil ang uppercase, lowercase, numero, ug espesyal nga karakter.',
    'err_pass_match': 'Dili magkaparehas ang mga password. Siguraduha nga managsama ang duha.',
    'err_username_taken': 'Kini nga username nakuha na. Pagpili og lain.',
    'err_email_taken': 'Kini nga email rehistrado na. Paggamit og lain.',
    'err_phone_taken': 'Kini nga numero gigamit na. Paggamit og lain.',
    'err_name_req': 'Ang imong tibuok pangalan gikinahanglan para sa rehistrasyon.',
    'err_name_format': 'Gamit lamang og mga letra ug espasyo para sa imong pangalan.',
    'err_phone_req': 'Gikinahanglan ang husto nga numero para sa pagmatuod.',
    'err_phone_format': 'Palihug isulod ang husto nga PH contact number (pananglitan, 09xxxxxxxxx).',
    'err_license_req': 'Gikinahanglan ang husto nga numero sa lisensya.',
    'err_license_format': 'Sayop nga format sa lisensya ang namatikdan.',
    'err_purok_req': 'Palihug pilia ang imong gipuy-an nga Purok.',
    'err_terms_req': 'Palihug basaha ug dawata ang Mga Termino ug Kondisyon.',
    'err_general': 'Palihug taronga ang mga highlighted nga sayop para mopadayon.',
    'err_network': 'Adunay network error. Palihug sulayi pag-usab unya.',
    'err_incorrect_password_attempts': 'Sayop nga password. {attempts} na lang ang nahabilin nga pagsulay.',
    'err_account_locked_final': 'Daghan na kaayo ang sayop nga pagsulay. Ang imong account naka-lock sulod sa 1 ka minuto.',

    // Permissions & Common
    'permissions_required': 'Gikinahanglan ang mga Permiso',
    'permissions_desc': 'Aron magamit ang Garbage Tracker, kinahanglan nimo i-enable ang Location Services ug tugutan ang Notifications. Kini magsiguro nga ang real-time tracking ug mga alerto sa koleksyon magtrabaho og husto.',
    'open_settings': 'Ablihi ang Settings',
    'go_back': 'Balik',
    'retry_connection': 'Sulayi Pag-usab ang Koneksyon',
    'no_internet': 'Walang Koneksyon sa Internet',
    'brgy_footer': '© 2026 Brgy. Balintawak Lipa City',
    'all_rights_reserved': 'Tanang katungod gigahin',
  };
}
