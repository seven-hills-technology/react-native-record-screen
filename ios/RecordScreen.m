#import "RecordScreen.h"
#import <React/RCTConvert.h>

@implementation RecordScreen

const int DEFAULT_FPS = 30;

- (NSDictionary *)errorResponse:(NSDictionary *)result;
{
    NSDictionary *json = [NSDictionary dictionaryWithObjectsAndKeys:
        @"error", @"status",
        result, @"result",nil];
    return json;

}

- (NSDictionary *) successResponse:(NSDictionary *)result;
{
    NSDictionary *json = [NSDictionary dictionaryWithObjectsAndKeys:
        @"success", @"status",
        result, @"result",nil];
    return json;

}

- (void) muteAudioInBuffer:(CMSampleBufferRef)sampleBuffer
{

    CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
    NSUInteger channelIndex = 0;

    CMBlockBufferRef audioBlockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t audioBlockBufferOffset = (channelIndex * numSamples * sizeof(SInt16));
    size_t lengthAtOffset = 0;
    size_t totalLength = 0;
    SInt16 *samples = NULL;
    CMBlockBufferGetDataPointer(audioBlockBuffer, audioBlockBufferOffset, &lengthAtOffset, &totalLength, (char **)(&samples));

    for (NSInteger i=0; i<numSamples; i++) {
        samples[i] = (SInt16)0;
    }
}

// H264は2または4の倍数の数値にしないと緑の縁が入ってしまうので、それを調整する関数
- (int) adjustMultipleOf2:(int)value;
{
    if (value % 2 == 1) {
        return value + 1;
    }
    return value;
}


RCT_EXPORT_MODULE()

RCT_EXPORT_METHOD(setup: (NSDictionary *)config)
{
    self.screenWidth = [RCTConvert int: config[@"width"]];
    self.screenHeight = [RCTConvert int: config[@"height"]];
    self.enableMic = [RCTConvert BOOL: config[@"mic"]];
    self.micDisabled = true;
}

RCT_REMAP_METHOD(startRecording, resolve:(RCTPromiseResolveBlock)resolve  reject:(RCTPromiseRejectBlock)reject)
{
    self.screenRecorder = [RPScreenRecorder sharedRecorder];
    if (self.screenRecorder.isRecording) {
        return;
    }
    
    self.encounteredFirstBuffer = NO;
    
    NSArray *pathDocuments = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *outputURL = pathDocuments[0];

    NSString *videoOutPath = [[outputURL stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"mp4"];
    
    
    NSError *error;
    self.writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:videoOutPath] fileType:AVFileTypeMPEG4 error:&error];
    if (!self.writer) {
        NSLog(@"writer: %@", error);
        abort();
    }
    
    AudioChannelLayout acl = { 0 };
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    self.audioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:@{ AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @(44100),  AVChannelLayoutKey: [NSData dataWithBytes: &acl length: sizeof( acl ) ], AVEncoderBitRateKey: @(64000)}];
    self.micInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:@{ AVFormatIDKey: @(kAudioFormatMPEG4AAC), AVSampleRateKey: @(44100),  AVChannelLayoutKey: [NSData dataWithBytes: &acl length: sizeof( acl ) ], AVEncoderBitRateKey: @(64000)}];
    
    self.audioInput.preferredVolume = 1.0;
    self.micInput.preferredVolume = 1.0;
    
    NSDictionary *compressionProperties = @{AVVideoProfileLevelKey         : AVVideoProfileLevelH264MainAutoLevel,
                                            AVVideoH264EntropyModeKey      : AVVideoH264EntropyModeCABAC,
                                            AVVideoAverageBitRateKey       : @(1920 * 1080 * 114),
                                            AVVideoMaxKeyFrameIntervalKey  : @60,
                                            AVVideoAllowFrameReorderingKey : @NO};

    NSLog(@"width: %d", [self adjustMultipleOf2:self.screenWidth]);
    NSLog(@"height: %d", [self adjustMultipleOf2:self.screenHeight]);
    if (@available(iOS 11.0, *)) {
        NSDictionary *videoSettings = @{
                                        AVVideoCodecKey                 : AVVideoCodecHEVC,
                                        AVVideoWidthKey                 : @([self adjustMultipleOf2:(self.screenWidth *2)]),
                                        AVVideoHeightKey                : @([self adjustMultipleOf2:(self.screenHeight *2)])};

        self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    } else {
        // Fallback on earlier versions
    }
    
    [self.writer addInput:self.micInput];
    [self.writer addInput:self.audioInput];
    [self.writer addInput:self.videoInput];
    [self.videoInput setMediaTimeScale:60];
    [self.writer setMovieTimeScale:60];
    [self.videoInput setExpectsMediaDataInRealTime:YES];

    if (self.enableMic) {
        self.screenRecorder.microphoneEnabled = YES;
    }
    
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                if (@available(iOS 11.0, *)) {
                    [self.screenRecorder startCaptureWithHandler:^(CMSampleBufferRef sampleBuffer, RPSampleBufferType bufferType, NSError* error) {
                        if (CMSampleBufferDataIsReady(sampleBuffer)) {
                            if (self.writer.status == AVAssetWriterStatusUnknown && !self.encounteredFirstBuffer && bufferType == RPSampleBufferTypeVideo) {
                                self.encounteredFirstBuffer = YES;
                                NSLog(@"First buffer video");
                                [self.writer startWriting];
                                [self.writer startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                            } else if (self.writer.status == AVAssetWriterStatusFailed) {
                                
                            }
                            
                            if (self.writer.status == AVAssetWriterStatusWriting) {
                                switch (bufferType) {
                                    case RPSampleBufferTypeVideo:
                                        if (self.videoInput.isReadyForMoreMediaData) {
                                            [self.videoInput appendSampleBuffer:sampleBuffer];
                                        }
                                        break;
                                    case RPSampleBufferTypeAudioApp:
                                        if (self.audioInput.isReadyForMoreMediaData) {
                                            [self.audioInput appendSampleBuffer:sampleBuffer];
                                        }
                                        break;
                                    case RPSampleBufferTypeAudioMic:
                                        if (self.micInput.isReadyForMoreMediaData) {
                                            if(self.enableMic && !self.micDisabled){
                                                [self.micInput appendSampleBuffer:sampleBuffer];
                                            } else {
                                                CMSampleBufferRef mutedBuffer = nil;
                                                CMSampleBufferCreateCopy(kCFAllocatorDefault, sampleBuffer, &mutedBuffer);
                                                [self muteAudioInBuffer:mutedBuffer];
                                                [self.micInput appendSampleBuffer:mutedBuffer];
                                            }
                                        }
                                        break;
                                    default:
                                        break;
                                }
                            }
                        }
                    } completionHandler:^(NSError* error) {
                        NSLog(@"startCapture: %@", error);
                        resolve(@"started");
                    }];
                } else {
                    // Fallback on earlier versions
                }
            } else {
                NSError* err = nil;
                reject(0, @"Permission denied", err);
            }
        });
    }];

    if (self.enableMic) {
        self.screenRecorder.microphoneEnabled = YES;
    }
}

RCT_REMAP_METHOD(stopRecording, tx:(double)tx ty:(double)ty w:(double)w h:(double)h resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 11.0, *)) {
            [[RPScreenRecorder sharedRecorder] stopCaptureWithHandler:^(NSError * _Nullable error) {
                if (!error) {
                    [self.audioInput markAsFinished];
                    [self.micInput markAsFinished];
                    [self.videoInput markAsFinished];
                    [self.writer finishWritingWithCompletionHandler:^{
                        NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObject:self.writer.outputURL.absoluteString forKey:@"outputURL"];
                        
                        
                        UISaveVideoAtPathToSavedPhotosAlbum(self.writer.outputURL.absoluteString, nil, nil, nil);
                        NSLog(@"finishWritingWithCompletionHandler: Recording stopped successfully. Cleaning up... %@", result);
                        AVAsset *videoAsset = [AVAsset assetWithURL:self.writer.outputURL];
                        [self cropVideo:videoAsset cropRectangle:CGRectMake(tx*2, ty*2, w*2, h*2) output:self.writer.outputURL completionHandler:^(NSString* path) {
                            [result setObject:path forKey:@"croppedPath"];
                            resolve([self successResponse:result]);
                            self.audioInput = nil;
                            self.micInput = nil;
                            self.videoInput = nil;
                            self.writer = nil;
                            self.screenRecorder = nil;
                        }];
                    }];
                }
            }];
        } else {
            // Fallback on earlier versions
        }
    });
}

RCT_REMAP_METHOD(clean,
                 cleanResolve:(RCTPromiseResolveBlock)resolve
                 cleanRejecte:(RCTPromiseRejectBlock)reject)
{

    NSArray *pathDocuments = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *path = pathDocuments[0];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    resolve(@"cleaned");
}

RCT_REMAP_METHOD(toggleMic,
                 toggleMicResolve: (RCTPromiseResolveBlock) resolve
                 toggleMicReject: (RCTPromiseRejectBlock) reject)
{
    self.micDisabled  = !self.micDisabled;
}

typedef enum {
    up, down, right, left
} Orientation;

- (Orientation) getOrientation:(AVAssetTrack *) track
{
    CGAffineTransform t = track.preferredTransform;
    
    if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0) {             // Portrait
        return up;
    } else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0) {      // PortraitUpsideDown
        return down;
    } else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0) {       // LandscapeRight
        return right;
    } else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0) {     // LandscapeLeft
        return left;
    } else {
        return up;
    }
}

- (void) cropVideo:(AVAsset *) video cropRectangle:(CGRect) cropRect output:(NSURL *) outputURL completionHandler:(void(^) (NSString*)) handler
{
    AVAssetTrack *track = [video tracksWithMediaType:AVMediaTypeVideo][0];
    CGAffineTransform transform = track.preferredTransform;
    CGSize originalSize = track.naturalSize;
    Orientation trackOrientation = [self getOrientation:track];
    bool cropRectIsPortrait = cropRect.size.width <= cropRect.size.height;
    
    //get actual display size of video
    CGSize videoSize;
    if ((transform.a == 0 && transform.b == 1 && transform.c == -1 && transform.d == 0) // rotate 90
        || (transform.a == 0 && transform.b == -1 && transform.c == 1 && transform.d == 0)) { // rotate -90
        videoSize = CGSizeMake(track.naturalSize.height,track.naturalSize.width);
    } else {
        videoSize = track.naturalSize;
    }
    
    AVMutableVideoComposition *videoComposition = [[AVMutableVideoComposition alloc] init];
    [videoComposition setRenderSize:cropRect.size];
    [videoComposition setFrameDuration:CMTimeMake(1, 30)];
    
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity);
    
    // shift video to be in the center
    AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    CGAffineTransform translation = CGAffineTransformMakeTranslation(- (cropRect.origin.x), -(cropRect.origin.y) );
    CGAffineTransform finalTransform = CGAffineTransformConcat(transform, translation);

    [transformer setTransform:finalTransform atTime:kCMTimeZero];
    instruction.layerInstructions = [NSArray arrayWithObject:transformer];
    videoComposition.instructions = [NSArray arrayWithObject: instruction];
    
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:video presetName:AVAssetExportPresetHighestQuality];
    [exporter setVideoComposition:videoComposition];
    NSString *path = [NSTemporaryDirectory() stringByAppendingString:@"export/video-cropped2.mp4"];
    NSFileManager *defaultManager = [NSFileManager defaultManager];
    [defaultManager createDirectoryAtPath:path withIntermediateDirectories:TRUE attributes:nil error:nil];
    if ([defaultManager fileExistsAtPath:path]) {
        [defaultManager removeItemAtPath:path error:nil];
    }
    NSURL *plsWork = [NSURL fileURLWithPath:path isDirectory:FALSE];
    [exporter setOutputURL: plsWork];
    [exporter setOutputFileType:AVFileTypeMPEG4];
    
    [exporter exportAsynchronouslyWithCompletionHandler:^(void) {
        NSLog(@"Export Status %d %@", exporter.status, exporter.error);
        handler(plsWork.path);
    }];
}

@end
