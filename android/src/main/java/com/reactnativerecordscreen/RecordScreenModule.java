package com.reactnativerecordscreen;

import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.media.MediaCodecInfo;
import android.media.MediaCodecList;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Environment;
import android.telecom.Call;
import android.util.Log;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.BaseActivityEventListener;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.Callback;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.WritableNativeMap;
import com.hbisoft.hbrecorder.HBRecorder;
import com.hbisoft.hbrecorder.HBRecorderListener;

import java.io.File;
import java.io.IOException;

import static java.lang.Math.ceil;

public class RecordScreenModule extends ReactContextBaseJavaModule implements HBRecorderListener {

    private final ReactApplicationContext reactContext;
    private Boolean mic= false;
    private HBRecorder hbRecorder;
    private File outputUri;
    private int SCREEN_RECORD_REQUEST_CODE = 1000;
    private Promise startPromise;
    private Promise stopPromise;

    public RecordScreenModule(ReactApplicationContext reactContext) {
        super(reactContext);
        this.reactContext = reactContext;
    }


    private final ActivityEventListener mActivityEventListener = new BaseActivityEventListener() {

        @Override
        public void onActivityResult(Activity activity, int requestCode, int resultCode, Intent intent) {
            if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
                if (resultCode == Activity.RESULT_CANCELED) {
                    startPromise.reject("403","Permission denied");
                } else if (resultCode == Activity.RESULT_OK) {
                    Log.d("ACCEPTED","accepted...");
                    hbRecorder.startScreenRecording(intent, resultCode, getCurrentActivity());
                }
                startPromise.resolve("started");
            }
        }
    };

    @Override
    public String getName() {
        return "RecordScreen";
    }

    public void setup(ReadableMap readableMap) {
//        int screenWidth = (readableMap.hasKey("width")) ? (int)ceil(readableMap.getDouble("width")) : 0;
//        int screenHeight = (readableMap.hasKey("height")) ? (int)ceil(readableMap.getDouble("height")) : 0;
        boolean mic =  (readableMap.hasKey("mic")) ? (boolean)readableMap.getBoolean("mic") : true;
        // TODO: Implement some actually useful functionality
//        callback.invoke("Received numberArgument: " + numberArgument + " stringArgument: " + stringArgument);
        hbRecorder= new HBRecorder(reactContext,this);
        hbRecorder.isAudioEnabled(mic);
        outputUri = this.reactContext.getExternalFilesDir("RecordScreen");
        // Log.d("OUTPUT", outputUri.getAbsolutePath());
        hbRecorder.setOutputPath(outputUri.toString());
        if(doesSupportEncoder("h264")){
            hbRecorder.setVideoEncoder("H264");
        }else{
            hbRecorder.setVideoEncoder("DEFAULT");
        }
        reactContext.addActivityEventListener(mActivityEventListener);
    }

    private void startRecordingScreen(){
        MediaProjectionManager mediaProjectionManager = (MediaProjectionManager) reactContext.getSystemService (Context.MEDIA_PROJECTION_SERVICE);
        Intent permissionIntent = mediaProjectionManager.createScreenCaptureIntent();
        getCurrentActivity().startActivityForResult(permissionIntent, SCREEN_RECORD_REQUEST_CODE);
    }

    @ReactMethod
    public void startRecording(Promise promise){
        startPromise = promise;
        try {
            startRecordingScreen();
        } catch (IllegalStateException e) {
            startPromise.reject("404",e.getMessage());
        }
    }

    @ReactMethod
    public void stopRecording(Promise promise){
        stopPromise=promise;
        hbRecorder.stopScreenRecording();
    }

    @Override
    public void HBRecorderOnStart() {
    Log.d("Started","Recording...");
    }

    @Override
    public void HBRecorderOnComplete() {
        Log.d("record completed","Completed");
        String uri = hbRecorder.getFilePath();
        WritableNativeMap response = new WritableNativeMap();
        WritableNativeMap result =  new WritableNativeMap();
        result.putString("outputURL", uri);
        response.putString("status", "success");
        response.putMap("result", result);
        stopPromise.resolve(response);
    }

    @Override
    public void HBRecorderOnError(int errorCode, String reason) {
        Log.d("Failed.","Failed to record "+reason);
        startPromise.resolve(reason);
    }

    private boolean doesSupportEncoder(String encoder) {
        int numCodecs = MediaCodecList.ALL_CODECS;
        for (int i=0; i<numCodecs; i++) {
            MediaCodecInfo codecInfo = MediaCodecList.getCodecInfoAt(i);
            if (codecInfo.isEncoder()) {
                if (codecInfo.getName() != null) {
                    if (codecInfo.getName().contains(encoder)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }
}
