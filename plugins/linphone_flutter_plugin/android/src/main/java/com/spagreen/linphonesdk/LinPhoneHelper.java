package com.spagreen.linphonesdk;

import android.app.Activity;
import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.gson.Gson;

import org.linphone.core.Account;
import org.linphone.core.AccountListener;
import org.linphone.core.AccountParams;
import org.linphone.core.Address;
import org.linphone.core.AudioDevice;
import org.linphone.core.AuthInfo;
import org.linphone.core.Call;
import org.linphone.core.CallLog;
import org.linphone.core.CallParams;
import org.linphone.core.ConferenceInfo;
import org.linphone.core.Core;
import org.linphone.core.CoreListener;
import org.linphone.core.CoreListenerStub;
import org.linphone.core.Factory;
import org.linphone.core.MediaEncryption;
import org.linphone.core.MessageWaitingIndication;
import org.linphone.core.PayloadType;              // ADDED
import org.linphone.core.RegistrationState;
import org.linphone.core.TransportType;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel;

public class LinPhoneHelper {
    private final String TAG = "linphonesdk-----------";
    private static Core core = null;
    private Context context;
    private String domain, userName, password;
    private EventChannelHelper loginListener;
    private EventChannelHelper callEventListener;


    public LinPhoneHelper(Activity context, EventChannelHelper loginListener, EventChannelHelper callEventListener) {
        this.context = context;
        this.loginListener = loginListener;
        this.callEventListener = callEventListener;
    }



public void login(String userName, String domain, String password) {

    this.domain = domain;
    this.userName = userName;
    this.password = password;

    Factory factory = Factory.instance();
    factory.setDebugMode(true, "LinPhoneSDKTest");

    core = factory.createCore(null, null, context);

    // Better transport for office WiFi
    // TransportType transportType = TransportType.Tcp;
    // TransportType transportType = TransportType.Tls;
    TransportType transportType = TransportType.Udp;


    // Disable problematic IPv6
    core.setIpv6Enabled(false);

    // Keep SIP alive
    // core.enableKeepAlive(true);
    core.setNetworkReachable(true);

    // Dynamic RTP ports
    core.setAudioPort(-1);

    // NAT traversal
    core.setNatPolicy(core.createNatPolicy());
    core.getNatPolicy().setStunEnabled(true);
    core.getNatPolicy().setIceEnabled(true);
    core.getNatPolicy().setStunServer("stun.l.google.com:19302");

    AuthInfo authInfo = Factory.instance().createAuthInfo(
            userName,
            null,
            password,
            null,
            null,
            domain,
            null
    );

    AccountParams params = core.createAccountParams();

    String sipAddress = "sip:" + userName + "@" + domain;

    Address identity = Factory.instance().createAddress(sipAddress);

    params.setIdentityAddress(identity);

    Address address = Factory.instance().createAddress("sip:" + domain);

    address.setTransport(transportType);

    params.setServerAddress(address);

    params.setRegisterEnabled(true);

    // Registration refresh
    params.setExpires(600);

    Account account = core.createAccount(params);

    core.addAuthInfo(authInfo);

    core.addAccount(account);

    core.setDefaultAccount(account);

    core.addListener(coreListener);

    core.start();

    // No SRTP for now
    core.setMediaEncryption(MediaEncryption.None);

    // Codec restriction
    PayloadType[] payloads = core.getAudioPayloadTypes();

    for (PayloadType pt : payloads) {

        String mime = pt.getMimeType();

        pt.enable(false);

        if (
                mime.equals("PCMU") ||
                mime.equals("PCMA") ||
                mime.equals("telephone-event")
        ) {
            pt.enable(true);
        }
    }

    core.setUserAgent("FlutterSoftphone", "2.0");
}

    // public void call(String number) {
    //     if (core == null) return;
    //     String formattedNumber = String.format("sip:%s@%s", number, domain);
    //     Address remoteAddress = Factory.instance().createAddress(formattedNumber);
    //     if (remoteAddress == null) return;
    //     CallParams params = core.createCallParams(null);
    //     if (params == null) return;

    //     // Disable encryption for this call
    //     params.setMediaEncryption(MediaEncryption.None);
    //     // Enable microphone
    //     params.setMicEnabled(true);

    //     core.inviteAddressWithParams(remoteAddress, params);
    // }
    public void call(String number) {
        if (core == null) return;

        String formattedNumber = String.format("sip:%s@%s", number, domain);
        Address remoteAddress = Factory.instance().createAddress(formattedNumber);
        if (remoteAddress == null) return;

        CallParams params = core.createCallParams(null);
        if (params == null) return;

        // Normal audio call
        params.setMediaEncryption(MediaEncryption.None);
        params.setMicEnabled(true);

        Call call = core.inviteAddressWithParams(remoteAddress, params);

        if (call != null) {
            try {
                call.setMicrophoneMuted(false);
            } catch (Exception e) {
                Log.e(TAG, "Failed to unmute outgoing call: " + e);
            }
        }
    }

    public boolean callForward(String destination) {
        if (core == null) return false;
        if (core.getCallsNb() == 0) return false;
        Call currentCall = null;
        if (core.getCurrentCall() == null) return false;
        currentCall = core.getCurrentCall();
        Address address = core.interpretUrl(destination);
        if (address == null) return false;
        currentCall.transferTo(address);
        return true;
    }

    public String callLogs() {
        if (core == null) return null;
        CallLog[] logs = core.getCallLogs();
        List<CallHistory> callHistoryList = new ArrayList<>();
        callHistoryList.clear();

        for (CallLog log : logs) {
            CallHistory history = new CallHistory();
            history.setNumber(log.getToAddress().getUsername());
            history.setStatus(log.getStatus().name());
            history.setDate(log.getStartDate());
            history.setDuration(log.getDuration());
            callHistoryList.add(history);
        }
        ListCallHistory list = new ListCallHistory();
        list.setCallHistoryList(callHistoryList);
        return new Gson().toJson(list);
    }


    public void hangUp() {
        if (core.getCallsNb() == 0) return;
        Call call = null;
        if (core.getCurrentCall() != null) {
            call = core.getCurrentCall();
        } else {
            call = core.getCalls()[0];
        }
        if (call == null) return;
        call.terminate();
        callEventListener.success("Released");
    }

    public boolean toggleMute() {
        if (core == null) return false;
        if (core.getCurrentCall() != null) {
            if (core.getCurrentCall().getMicrophoneMuted()) {
                core.getCurrentCall().setMicrophoneMuted(false);
                return false;
            } else {
                core.getCurrentCall().setMicrophoneMuted(true);
                return true;
            }
        }
        return false;
    }

    public void toggleSpeaker() {
        // Get the currently used audio device
        AudioDevice currentAudioDevice = core.getCurrentCall().getOutputAudioDevice();
        boolean speakerEnabled = currentAudioDevice.getType() == AudioDevice.Type.Speaker;

        Log.e(TAG, "--------------toggleSpeaker: " + speakerEnabled);
        Log.e(TAG, "--------------toggleSpeaker: " + currentAudioDevice.getType());

        for (int i = 0; i < core.getAudioDevices().length; i++) {
            AudioDevice audioDevice = core.getAudioDevices()[i];
            if (speakerEnabled && audioDevice.getType() == AudioDevice.Type.Earpiece) {
                core.getCurrentCall().setOutputAudioDevice(audioDevice);
                return;
            } else if (!speakerEnabled && audioDevice.getType() == AudioDevice.Type.Speaker) {
                core.getCurrentCall().setOutputAudioDevice(audioDevice);
                return;
            }
        }
    }

    // public void answerCall() {
    //     if (core.getCallsNb() == 0) return;
    //     Call call = core.getCurrentCall();
    //     if (call == null) call = core.getCalls()[0];
    //     if (call == null) return;
    //     CallParams params = core.createCallParams(call);
    //     if (params == null) return;
    //     call.acceptWithParams(params);
    //     callEventListener.success("CallAnswered");
    // }

    public void answerCall() {
    if (core == null || core.getCallsNb() == 0) return;
    Call call = core.getCurrentCall();
    if (call == null) call = core.getCalls()[0];
    if (call == null) return;

    CallParams params = core.createCallParams(call);
    if (params == null) return;

    // Enable microphone and disable encryption for incoming call
    params.setMicEnabled(true);
    params.setMediaEncryption(MediaEncryption.None);

    call.acceptWithParams(params);
    call.setMicrophoneMuted(false);
    callEventListener.success("CallAnswered");
}

    public void rejectCall() {
        if (core.getCallsNb() == 0) return;
        Call call = core.getCurrentCall();
        if (call == null) call = core.getCalls()[0];
        if (call == null) return;
        call.terminate();
        callEventListener.success("CallRejected");
    }
    
    public void removeLoginListener() {
        if (core == null) return;
        core.removeListener(coreListener);
        core = null;
        loginListener.handler = null;
    }

    public void removeCallListener() {
        if (core == null) return;
        core.removeListener(coreListener);
        core = null;
        callEventListener.handler = null;
    }

    CoreListener coreListener = new CoreListenerStub() {
        @Override
        public void onAccountRegistrationStateChanged(@NonNull Core core, @NonNull Account account, RegistrationState state, @NonNull String message) {
            loginListener.success(state.name());
        }

        @Override
        public void onCallStateChanged(@NonNull Core core, @NonNull Call call, Call.State state, @NonNull String message) {
            switch (state) {
                case IncomingReceived:
                    Log.e(TAG, "onCallStateChanged: Incoming Received");
                    callEventListener.success(state.name());
                    break;
                case OutgoingInit:
                    Log.e(TAG, "onCallStateChanged: Outgoing init");
                    callEventListener.success(state.name());
                    break;
                case OutgoingProgress:
                    Log.e(TAG, "onCallStateChanged: Outgoing Progress");
                    callEventListener.success(state.name());
                    break;
                case OutgoingRinging:
                    Log.e(TAG, "onCallStateChanged: Ringing");
                    callEventListener.success(state.name());
                    break;
                // case Connected:
                //     Log.e(TAG, "onCallStateChanged: Connected");
                //     callEventListener.success(state.name());
                //     break;
                // case StreamsRunning:
                //     Log.e(TAG, "onCallStateChanged: StreamsRunning");
                //     callEventListener.success(state.name());
                //     break;
                // case Paused:
                //     Log.e(TAG, "onCallStateChanged: Paused");
                //     callEventListener.success(state.name());
                //     break;
                // case PausedByRemote:
                //     Log.e(TAG, "onCallStateChanged: PausedByRemote");
                //     callEventListener.success(state.name());
                //     break;
                case Connected:
                    Log.e(TAG, "onCallStateChanged: Connected");
                    try {
                        call.setMicrophoneMuted(false);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to unmute on Connected: " + e);
                    }
                    callEventListener.success(state.name());
                    break;

                case StreamsRunning:
                    Log.e(TAG, "onCallStateChanged: StreamsRunning");
                    try {
                        call.setMicrophoneMuted(false);
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to unmute on StreamsRunning: " + e);
                    }
                    callEventListener.success(state.name());
                    break;

                case Paused:
                    Log.e(TAG, "onCallStateChanged: Paused - unexpected local hold detected, resuming call");
                    try {
                        call.resume();
                        call.setMicrophoneMuted(false);
                        callEventListener.success("AutoResumedFromPaused");
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to auto-resume paused call: " + e);
                        callEventListener.success(state.name());
                    }
                    break;

                case PausedByRemote:
                    Log.e(TAG, "onCallStateChanged: PausedByRemote");
                    callEventListener.success(state.name());
                    break;
                case Updating:
                    Log.e(TAG, "onCallStateChanged: Updating");
                    callEventListener.success(state.name());
                    break;
                case UpdatedByRemote:
                    Log.e(TAG, "onCallStateChanged: UpdatedByRemote");
                    callEventListener.success(state.name());
                    break;
                case Released:
                    Log.e(TAG, "onCallStateChanged: Released");
                    callEventListener.success(state.name());
                    break;
                case EarlyUpdatedByRemote:
                    Log.e(TAG, "onCallStateChanged: EarlyUpdatedByRemote");
                    callEventListener.success(state.name());
                case Error:
                    Log.e(TAG, "onCallStateChanged: Error");
                    callEventListener.success(state.name());
                    break;
            }
        }
    };
}