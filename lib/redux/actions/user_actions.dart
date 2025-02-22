import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_segment/flutter_segment.dart';
import 'package:fusecash/common/di/di.dart';
import 'package:country_code_picker/country_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fusecash/common/router/routes.dart';
import 'package:fusecash/constants/enums.dart';
import 'package:fusecash/constants/urls.dart';
import 'package:fusecash/constants/variables.dart';
import 'package:fusecash/models/user_state.dart';
import 'package:fusecash/models/wallet/wallet_modules.dart';
import 'package:fusecash/redux/actions/cash_wallet_actions.dart';
import 'package:fusecash/utils/addresses.dart';
import 'package:fusecash/utils/contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phone_number/phone_number.dart';
import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_core/wallet_core.dart';
import 'package:fusecash/services.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:fusecash/utils/phone.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_udid/flutter_udid.dart';
import 'package:fusecash/utils/log/log.dart';

Future<bool> approvalCallback() async {
  return true;
}

class UpdateCurrency {
  final String currency;
  UpdateCurrency({required this.currency});
}

class UpdateLocale {
  final Locale locale;
  UpdateLocale({required this.locale});
}

class WarnSendDialogShowed {
  final bool value;
  WarnSendDialogShowed(
    this.value,
  );
}

class HomeBackupDialogShowed {
  HomeBackupDialogShowed();
}

class ReceiveBackupDialogShowed {
  ReceiveBackupDialogShowed();
}

class DepositBannerShowed {
  DepositBannerShowed();
}

class SetSecurityType {
  BiometricAuth biometricAuth;
  SetSecurityType({required this.biometricAuth});
}

class CreateLocalAccountSuccess {
  final List<String> mnemonic;
  final String privateKey;
  final String accountAddress;
  CreateLocalAccountSuccess(
    this.mnemonic,
    this.privateKey,
    this.accountAddress,
  );
}

class ReLogin {
  ReLogin();
}

class LoginRequestSuccess {
  final CountryCode countryCode;
  final String phoneNumber;
  final String? displayName;
  final String? email;
  LoginRequestSuccess({
    required this.countryCode,
    required this.phoneNumber,
    this.displayName,
    this.email,
  });
}

class LogoutRequestSuccess {
  LogoutRequestSuccess();
}

class LoginVerifySuccess {
  final String jwtToken;
  LoginVerifySuccess(this.jwtToken);
}

class SyncContactsProgress {
  List<String> contacts;
  List<Map<String, dynamic>> newContacts;
  SyncContactsProgress(this.contacts, this.newContacts);
}

class SyncContactsRejected {
  SyncContactsRejected();
}

class SaveContacts {
  List<Contact> contacts;
  SaveContacts(this.contacts);
}

class SetPincodeSuccess {
  String pincode;
  SetPincodeSuccess(this.pincode);
}

class SetDisplayName {
  String displayName;
  SetDisplayName(this.displayName);
}

class SetUserAvatar {
  String avatarUrl;
  SetUserAvatar(this.avatarUrl);
}

class BackupRequest {
  BackupRequest();
}

class BackupSuccess {
  BackupSuccess();
}

class SetCredentials {
  PhoneAuthCredential? credentials;
  SetCredentials(this.credentials);
}

class SetVerificationId {
  String verificationId;
  SetVerificationId(this.verificationId);
}

class JustInstalled {
  final DateTime installedAt;
  JustInstalled(this.installedAt);
}

class DeviceIdSuccess {
  final String identifier;
  DeviceIdSuccess(this.identifier);
}

ThunkAction loginHandler(
  CountryCode countryCode,
  PhoneNumber phoneNumber,
  Function onSuccess,
  Function(dynamic error) onError,
) {
  return (Store store) async {
    try {
      store.dispatch(setDeviceId());
      Segment.alias(alias: phoneNumber.e164);
      Segment.track(
        eventName: 'Sign up: Phone_NextBtn_Press',
      );
      await onBoardStrategy.login(
        store,
        phoneNumber.e164,
        () {
          store.dispatch(
            LoginRequestSuccess(
              countryCode: countryCode,
              phoneNumber: phoneNumber.e164,
            ),
          );
          onSuccess();
        },
        (e) async {
          Segment.track(
            eventName: 'Sign up: FAILED - Phone_NextBtn_Press',
            properties: Map.from({"error": e.toString()}),
          );
          onError(e.toString());
          await Sentry.captureMessage(
              'Error in login with phone number: ${e.toString()}');
        },
      );
    } catch (e, s) {
      log.error(
        'ERROR - Login Request',
        error: e,
        stackTrace: s,
      );
      onError(e);
      Segment.track(
        eventName: 'Sign up: FAILED - Phone_NextBtn_Press',
        properties: Map.from({"error": e.toString()}),
      );
      await Sentry.captureException(
        Exception('Error in login with phone number: ${e.toString()}'),
        stackTrace: s,
        hint: 'ERROR in Login Request',
      );
    }
  };
}

ThunkAction verifyHandler(
  String verificationCode,
  Function onSuccess,
  Function(dynamic error) onError,
) {
  return (Store store) async {
    try {
      Segment.track(
        eventName: 'Sign up: Verify phone code next button pressed',
      );
      await onBoardStrategy.verify(
        store,
        verificationCode,
        (String jwtToken) {
          log.info('jwtToken $jwtToken');
          Segment.track(
            eventName: 'Sign up: VerificationCode_NextBtn_Press',
          );
          store.dispatch(LoginVerifySuccess(jwtToken));
          api.setJwtToken(jwtToken);
          walletApi.setJwtToken(jwtToken);
          onSuccess();
          rootRouter.push(UserNameScreen());
        },
      );
    } catch (error, s) {
      onError(error.toString());
      Segment.track(
        eventName: 'Sign up: FAILED - VerificationCode_NextBtn_Press',
        properties: Map.from({
          "error": error.toString(),
        }),
      );
      await Sentry.captureException(
        Exception('Error in verify phone number: ${error.toString()}'),
        stackTrace: s,
        hint: 'Error while phone number verification',
      );
    }
  };
}

ThunkAction backupWalletCall() {
  return (Store store) async {
    if (store.state.userState.backup) return;
    try {
      String communityAddress = store.state.cashWalletState.communityAddress;
      store.dispatch(BackupRequest());
      await walletApi.backupWallet(communityAddress: communityAddress);
      store.dispatch(BackupSuccess());
    } catch (e) {
      store.dispatch(BackupSuccess());
    }
  };
}

ThunkAction restoreWalletCall(
  List<String> _mnemonic,
  VoidCallback successCallback,
  VoidCallback failureCallback,
) {
  return (Store store) async {
    try {
      log.info('restore wallet');
      String mnemonic = _mnemonic.join(' ');
      log.info('mnemonic: $mnemonic');
      log.info('compute pk');
      String privateKey = await compute(
        Web3.privateKeyFromMnemonic,
        mnemonic,
      );
      Credentials credentials = EthPrivateKey.fromHex(privateKey);
      EthereumAddress accountAddress = await credentials.extractAddress();
      log.info('privateKey: $privateKey');
      log.info('accountAddress: ${accountAddress.toString()}');
      store.dispatch(
        CreateLocalAccountSuccess(
          mnemonic.split(' '),
          privateKey,
          accountAddress.toString(),
        ),
      );
      store.dispatch(
        SetDefaultCommunity(
          defaultCommunityAddress.toLowerCase(),
        ),
      );
      successCallback();
      Segment.track(
        eventName: 'Existing User: Successful Restore wallet from backup',
      );
    } catch (e, s) {
      log.error(
        'ERROR - restoreWalletCall',
        error: e,
        stackTrace: s,
      );
      Segment.track(
        eventName: 'Existing User: Failed to restore wallet from backup',
      );
      failureCallback();
      await Sentry.captureException(
        Exception('Error in restore mnemonic: ${e.toString()}'),
        stackTrace: s,
        hint: 'ERROR in restore wallet',
      );
    }
  };
}

ThunkAction setDeviceId() {
  return (Store store) async {
    String identifier = await FlutterUdid.udid;
    log.info("device identifier: $identifier");
    store.dispatch(DeviceIdSuccess(identifier));
  };
}

ThunkAction createLocalAccountCall(
  VoidCallback successCallback,
  VoidCallback errorCallback,
) {
  return (Store store) async {
    try {
      log.info('create wallet');
      String mnemonic = Web3.generateMnemonic();
      log.info('mnemonic: $mnemonic');
      log.info('compute pk');
      String privateKey = await compute(
        Web3.privateKeyFromMnemonic,
        mnemonic,
      );
      Credentials credentials = EthPrivateKey.fromHex(privateKey);
      EthereumAddress accountAddress = await credentials.extractAddress();
      log.info('privateKey: $privateKey');
      log.info('accountAddress: ${accountAddress.toString()}');
      store.dispatch(
        CreateLocalAccountSuccess(
          mnemonic.split(' '),
          privateKey,
          accountAddress.toString(),
        ),
      );
      store
          .dispatch(SetDefaultCommunity(defaultCommunityAddress.toLowerCase()));
      Segment.track(
        eventName: 'New User: Create Wallet',
      );
      successCallback();
    } catch (e, s) {
      log.error(
        'ERROR - createLocalAccountCall',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(
        Exception('Error in generate mnemonic: ${e.toString()}'),
        stackTrace: s,
        hint: 'ERROR while generate mnemonic',
      );
      errorCallback();
    }
  };
}

ThunkAction logoutCall() {
  return (Store store) async {
    store.dispatch(LogoutRequestSuccess());
  };
}

ThunkAction reLoginCall() {
  return (Store store) async {
    store.dispatch(ReLogin());
    store.dispatch(getWalletAddressesCall());
  };
}

ThunkAction syncContactsCall() {
  return (Store store) async {
    try {
      List<Contact> contacts = List.from(await Contacts.getContacts());
      store.dispatch(SaveContacts(contacts));
      List<String> syncedContacts = store.state.userState.syncedContacts;
      List<String> newPhones = <String>[];
      String countryCode = store.state.userState.countryCode;
      String isoCode = store.state.userState.isoCode;
      for (Contact contact in contacts) {
        Future<List<String>> phones = Future.wait(
          contact.phones!.map(
            (Item phone) async {
              String value = clearNotNumbersAndPlusSymbol(phone.value!);
              try {
                PhoneNumber phoneNumber = await phoneNumberUtil.parse(value);
                return phoneNumber.e164;
              } catch (e) {
                String formatted = formatPhoneNumber(value, countryCode);
                bool isValid = await phoneNumberUtil
                    .validate(formatted, isoCode)
                    .catchError(
                      (erro) => false,
                    );
                if (isValid) {
                  String phoneNum =
                      await phoneNumberUtil.format(formatted, isoCode);
                  PhoneNumber phoneNumber =
                      await phoneNumberUtil.parse(phoneNum);
                  return phoneNumber.e164;
                }
                return '';
              }
            },
          ),
        );
        List<String> result = await phones;
        result = result.toSet().toList()
          ..removeWhere((element) => element == '');
        for (String phone in result) {
          if (!syncedContacts.contains(phone)) {
            newPhones.add(phone);
          }
        }
      }
      if (newPhones.length == 0) {
        dynamic response = await walletApi.syncContacts(newPhones);
        store.dispatch(SyncContactsProgress(newPhones,
            List<Map<String, dynamic>>.from(response['newContacts'])));
        await walletApi.ackSync(response['nonce']);
      } else {
        int limit = 100;
        List<String> partial = newPhones.take(limit).toList();
        while (partial.length > 0) {
          dynamic response = await walletApi.syncContacts(partial);
          store.dispatch(
            SyncContactsProgress(
              partial,
              List<Map<String, dynamic>>.from(
                response['newContacts'],
              ),
            ),
          );

          await walletApi.ackSync(response['nonce']);
          newPhones = newPhones.sublist(partial.length);
          partial = newPhones.take(limit).toList();
        }
      }
    } catch (e, s) {
      log.error(
        'ERROR - syncContactsCall',
        error: e,
        stackTrace: s,
      );
    }
  };
}

ThunkAction identifyCall({String? wallet}) {
  return (Store store) async {
    UserState userState = store.state.userState;
    String displayName = userState.displayName;
    String phoneNumber = userState.phoneNumber;
    String walletAddress = wallet ?? userState.walletAddress;
    String accountAddress = userState.accountAddress;
    String identifier = userState.identifier;
    Sentry.configureScope((scope) {
      scope.user = SentryUser(
        id: phoneNumber,
        username: displayName,
      );
      scope.setContexts(
        'user',
        Map.from({
          'walletAddress': walletAddress,
          'accountAddress': accountAddress,
        }),
      );
    });

    store.dispatch(segmentIdentifyCall(
      Map<String, dynamic>.from({
        "Phone Number": phoneNumber,
        "Wallet Address": walletAddress,
        "Account Address": accountAddress,
        "Display Name": displayName,
        "Identifier": identifier,
      }),
    ));
    if (Platform.isAndroid) {
      try {
        final String token = (await getIt<FirebaseMessaging>().getToken())!;
        log.info("Firebase messaging token $token");
        await Segment.setContext({
          'device': {'token': token},
        });
      } catch (e, s) {
        log.error('Error in identifyCall: ${e.toString()} ${s.toString()}');
      }
    }
    try {
      await walletApi.addUserContext({
        'os': Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : 'other',
      });
    } catch (e, s) {
      log.error(
        'Error in api.addUserContext',
        error: e,
        stackTrace: s,
      );
    }
  };
}

ThunkAction saveUserProfile(walletAddress) {
  return (Store store) async {
    String displayName = store.state.userState.displayName;
    try {
      Map<String, dynamic> userProfile =
          await walletApi.getUserProfile(walletAddress);
      if (userProfile.isNotEmpty) {
        if (userProfile.containsKey('avatarHash')) {
          store.dispatch(SetUserAvatar(userProfile['imageUri']));
        }
      }
    } catch (e) {
      Map user = {
        "accountAddress": walletAddress,
        "email": 'wallet-user@fuse.io',
        "provider": 'HDWallet',
        "subscribe": false,
        "source": 'wallet-v2',
        "displayName": displayName
      };
      await walletApi.saveUserProfile(user);
    }
  };
}

ThunkAction loadContacts() {
  return (Store store) async {
    try {
      bool isPermitted = await Contacts.checkPermissions();
      if (isPermitted) {
        store.dispatch(syncContactsCall());
      }
    } catch (e, s) {
      log.error(
        'ERROR - load contacts',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(
        Exception('Error in load contacts: ${e.toString()}'),
        stackTrace: s,
        hint: 'ERROR check Contacts Permissions',
      );
    }
  };
}

ThunkAction setupWalletCall(Map<String, dynamic> walletData) {
  return (Store store) async {
    try {
      final List<String> networks = List<String>.from(walletData['networks']);
      final String walletAddress = walletData['walletAddress'];
      final String privateKey = store.state.userState.privateKey;
      final bool backup =
          walletData.containsKey('backup') ? walletData['backup'] : false;
      final WalletModules walletModules = WalletModules.fromJson(
        walletData['walletModules'],
      );
      store.dispatch(
        GetWalletDataSuccess(
          backup: backup,
          walletAddress: walletAddress,
          networks: networks,
          walletModules: walletModules,
        ),
      );
      if (!getIt.isRegistered<Web3>(instanceName: 'fuseWeb3')) {
        getIt.registerSingleton<Web3>(
          Web3(
            approveCb: approvalCallback,
            url: UrlConstants.FUSE_RPC_URL,
            networkId: Variables.FUSE_CHAIN_ID,
            defaultCommunityAddress: defaultCommunityAddress,
            communityManagerAddress: walletModules.communityManager,
            transferManagerAddress: walletModules.transferManager,
            daiPointsManagerAddress: walletModules.daiPointsManager,
          ),
          instanceName: 'fuseWeb3',
        );
        await getIt<Web3>(instanceName: 'fuseWeb3').setCredentials(privateKey);
      }
    } catch (e, s) {
      log.error(
        'ERROR - setupWalletCall',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(
        e,
        stackTrace: s,
        hint: 'ERROR - setupWalletCall $e',
      );
    }
  };
}

ThunkAction getWalletAddressesCall() {
  return (Store store) async {
    try {
      final dynamic walletData = await walletApi.getWallet();
      final Map<String, dynamic> data = Map<String, dynamic>.from({
        ...walletData,
      });
      store.dispatch(setupWalletCall(data));
    } catch (e, s) {
      log.error(
        'ERROR - getWalletAddressCall',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(
        e,
        stackTrace: s,
        hint: 'ERROR - getWalletAddressCall $e',
      );
    }
  };
}

ThunkAction updateDisplayNameCall(String displayName) {
  return (Store store) async {
    try {
      String walletAddress = store.state.userState.walletAddress;
      if (walletAddress.isNotEmpty) {
        await walletApi.updateDisplayName(walletAddress, displayName);
        store.dispatch(SetDisplayName(displayName));
      }
    } catch (e, s) {
      log.error(
        'ERROR - updateDisplayNameCall',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(e, stackTrace: s);
    }
  };
}

ThunkAction updateUserAvatarCall(ImageSource source) {
  return (Store store) async {
    final file = await ImagePicker().pickImage(source: source);
    try {
      final uploadResponse = await api.uploadImage(File(file!.path));
      String walletAddress = store.state.userState.walletAddress;
      if (walletAddress.isNotEmpty) {
        await walletApi.updateAvatar(walletAddress, uploadResponse['hash']);
        store.dispatch(SetUserAvatar(uploadResponse['uri']));
      }
    } catch (e, s) {
      log.error(
        'ERROR - updateUserAvatarCall',
        error: e,
        stackTrace: s,
      );
      await Sentry.captureException(e, stackTrace: s);
    }
  };
}
