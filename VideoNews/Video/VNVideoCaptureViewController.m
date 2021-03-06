//
//  VNVideoCaptureViewController.m
//  VideoNews
//
//  Created by zhangxue on 14-7-20.
//  Copyright (c) 2014年 Manyu Zhu. All rights reserved.
//

#import "VNVideoCaptureViewController.h"
#import "VNCameraOverlayView.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import "VNHTTPRequestManager.h"
#import <AFNetworking.h>

#import "VNVideoCustomizationController.h"

@interface VNVideoCaptureViewController () <AVCaptureFileOutputRecordingDelegate,VNCameraOverlayViewDelegate,UIAlertViewDelegate>


@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDeviceInput *videoInput;
@property (nonatomic, strong) AVCaptureDeviceInput *audioInput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;

@property (nonatomic, strong) VNCameraOverlayView *overlayView;

@property (nonatomic, strong) NSMutableArray *videoPathArr;
@property (nonatomic, strong) NSMutableArray *videoTimePointArr;

@property (nonatomic, assign) CGFloat videoTotalDuration;
@property (nonatomic, assign) NSInteger videoPieceCount;

@property (nonatomic, strong) NSTimer *durationTimer;

@end

@implementation VNVideoCaptureViewController

#define MIN_VIDEO_DURATION 5.0
#define MAX_VIDEO_DURATION 30.0
#define TEMP_VIDEO_NAME_PREFIX @"VN_Video_"
#define screenH ([[UIScreen mainScreen] bounds].size.height)

static NSString *videoFilePath;

#pragma mark - Initialization

- (VNCameraOverlayView *)overlayView
{
    if (!_overlayView) {
        _overlayView = [[VNCameraOverlayView alloc] initWithFrame:self.view.frame];
        _overlayView.delegate = self;
//        [_overlayView setProgressViewBlinking:YES];
    }
    return _overlayView;
}

#pragma mark - ViewLifeCycle

- (id)init
{
    self = [super init];
    if (self) {
        
        self.view.backgroundColor = [UIColor blackColor];
        
        videoFilePath = [VNUtility getNSCachePath:@"VideoFiles"];
        
        _videoTimePointArr = [NSMutableArray arrayWithCapacity:1];
        _videoPathArr = [NSMutableArray arrayWithCapacity:1];
        self.videoPieceCount = 0;
        self.videoTotalDuration = 0;
        
        [self initCaptureSession];
        [self initDir];
        
    }
    return self;
}

- (id)initWithVideoClips
{
    self = [super init];
    if (self) {
        
        self.view.backgroundColor = [UIColor blackColor];

        videoFilePath = [VNUtility getNSCachePath:@"VideoFiles"];
        
        _videoTimePointArr = [NSMutableArray arrayWithCapacity:1];
        _videoPathArr = [NSMutableArray arrayWithCapacity:1];
        self.videoPieceCount = 0;
        self.videoTotalDuration = 0;
        
        NSString *clipsFilePath = [videoFilePath stringByAppendingPathComponent:@"Clips"];
        
        NSArray *arr = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:clipsFilePath error:nil];
        
        if (arr && arr.count > 0) {
            for (NSString *path in arr) {
                
                NSString *filePath = [clipsFilePath stringByAppendingPathComponent:path];
                [_videoPathArr addObject:filePath];
                
                AVAsset *anAsset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:filePath] options:nil];
                float currVideoDuration = anAsset.duration.value / anAsset.duration.timescale;
                
                self.videoPieceCount++;
                
                self.videoTotalDuration += currVideoDuration;
                
                [_videoTimePointArr addObject:[NSNumber numberWithFloat:self.videoTotalDuration]];
            }
        }
        
        [self initCaptureSession];
        [self initDir];
        
        CGFloat percent = self.videoTotalDuration / 30.0 ;
        [_overlayView setProgressTimeArr:_videoTimePointArr];
        [_overlayView updateProgressViewToPercentage:percent];
        [_overlayView setTrashBtnEnabled:YES];
        if (self.videoTotalDuration < MIN_VIDEO_DURATION) {
            [self.overlayView setAlbumAndSubmitBtnStatus:NO];
        }else {
            [self.overlayView setAlbumAndSubmitBtnStatus:YES];
        }
        
        NSString *cropFilePath = [videoFilePath stringByAppendingPathComponent:@"Temp/VN_Video_Cropped.mp4"];
        
        BOOL existCropFile = [[NSFileManager defaultManager] fileExistsAtPath:cropFilePath];
        if (existCropFile) {
            
            __weak VNVideoCaptureViewController *weakSelf = self;
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                VNVideoCustomizationController *coverSettingCtl = [[VNVideoCustomizationController alloc] init];
                coverSettingCtl.videoPath = cropFilePath;
                [weakSelf.navigationController pushViewController:coverSettingCtl animated:NO];
            });
        }
        
    }
    return self;
}

- (void) initCaptureSession
{
    
    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        [_captureSession setSessionPreset:AVCaptureSessionPresetMedium];
    }

    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [videoDevice lockForConfiguration:nil];
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    
    _videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    _audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    
    if (!_videoInput) {
        
        __weak VNVideoCaptureViewController *weakSelf = self;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"程序没有权限访问您的摄像头，请在隐私设置中开启。" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [alert show];
            
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        });
        
    }else {
        [self.captureSession addInput:self.videoInput];
        [self.captureSession addInput:self.audioInput];
        [self.captureSession addOutput:self.movieOutput];
        
        AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.captureSession];
        CGFloat y;
        if (screenH == 568) {
            y = -6;
        }else {
            y = 0;
        }
        previewLayer.frame = CGRectMake(0, y, self.view.frame.size.width, self.view.frame.size.height);
        [self.view.layer addSublayer:previewLayer];
        
        [self.view addSubview:self.overlayView];
    }

}

- (void)initDir
{
    BOOL _isDir;
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:[videoFilePath stringByAppendingPathComponent:@"Clips"] isDirectory:&_isDir]){
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[videoFilePath stringByAppendingPathComponent:@"Clips"] withIntermediateDirectories:YES attributes:nil error:nil]) {
            
        }
    }
    
    if(![[NSFileManager defaultManager] fileExistsAtPath:[videoFilePath stringByAppendingPathComponent:@"Temp"] isDirectory:&_isDir]){
        if (![[NSFileManager defaultManager] createDirectoryAtPath:[videoFilePath stringByAppendingPathComponent:@"Temp"] withIntermediateDirectories:YES attributes:nil error:nil]) {
            
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
 
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearVideoClips) name:@"ClearVideoClipsNotification" object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    __weak VNVideoCaptureViewController *weakSelf = self;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.captureSession startRunning];
    });
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.captureSession stopRunning];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

}

- (void)dealloc
{
    self.overlayView.delegate = nil;
}

#pragma mark - Methods

- (void)clearVideoClips
{
    [_videoTimePointArr removeAllObjects];
    [_videoPathArr removeAllObjects];
    self.videoPieceCount = 0;
    self.videoTotalDuration = 0;

    [_overlayView setProgressTimeArr:_videoTimePointArr];
    [_overlayView updateProgressViewToPercentage:0];
    [_overlayView setTrashBtnEnabled:NO];
    [self.overlayView setAlbumAndSubmitBtnStatus:NO];

}

- (void)refreshVideoDuration:(NSTimer *)timer
{
    self.videoTotalDuration += 0.1;
    
    CGFloat percent = self.videoTotalDuration / 30.0 ;
    [_overlayView updateProgressViewToPercentage:percent];
    
    if (self.videoTotalDuration < MIN_VIDEO_DURATION) {
        [self.overlayView setAlbumAndSubmitBtnStatus:NO];
    }else {
        [self.overlayView setAlbumAndSubmitBtnStatus:YES];
    }
    if (self.videoTotalDuration >= MAX_VIDEO_DURATION) {
        
        [self doEndCurVideo];
        
    }
}

/**
 *  @description: combine those video clips in temp directory to a single video,
 *                and then crop them to fit the crop frame.
 */
- (void)combineAndCropSingleVideo
{
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    
    AVMutableCompositionTrack *compositionVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    
    AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    CMTime startTime = kCMTimeZero;
    
    //for loop to combine clips into a single video
    for (NSInteger i=0; i < self.videoPathArr.count; i++) {
        
        NSString *pathString = [NSString stringWithString:[self.videoPathArr objectAtIndex:i]];
        
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:pathString] options:nil];
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        
        AVAssetTrack *audioTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
        
        //set the orientation
        if(i == 0)
        {
            [compositionVideoTrack setPreferredTransform:videoTrack.preferredTransform];
        }
        
        BOOL ok;
        ok = [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, [asset duration]) ofTrack:videoTrack atTime:startTime error:nil];
        ok = [compositionAudioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, [asset duration]) ofTrack:audioTrack atTime:startTime error:nil];
        
        startTime = CMTimeAdd(startTime, [asset duration]);
    }
    
    //export the combined video
    
    NSString *combinedPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Temp/%@Combined.mov",TEMP_VIDEO_NAME_PREFIX]];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:combinedPath error:nil];
    });

    __weak VNVideoCaptureViewController *weakSelf = self;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        NSURL *url = [NSURL fileURLWithPath:combinedPath];
        
        AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
        exporter.outputURL = url;
        exporter.outputFileType = AVFileTypeQuickTimeMovie;
        
        [exporter exportAsynchronouslyWithCompletionHandler:^{
            
            dispatch_async(dispatch_get_main_queue(), ^{
                switch ([exporter status]) {
                    case AVAssetExportSessionStatusFailed:
                    {
                        NSLog(@"111111Export failed: %@", [[exporter error] localizedDescription]);
                    }
                        break;
                    case AVAssetExportSessionStatusCancelled:
                    {
                        NSLog(@"111111Export canceled");
                    }
                        break;
                    default:
                        [weakSelf cropSingleVideo];
                        
                        break;
                }
            });
        }];

    });
}

- (void)cropSingleVideo
{
    
    /*******************************************************************************************/
    
    NSString *combinedPath;
    if (self.videoPieceCount == 1) {
        combinedPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Clips/%@1.mov",TEMP_VIDEO_NAME_PREFIX]];
    }else {
        combinedPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Temp/%@Combined.mov",TEMP_VIDEO_NAME_PREFIX]];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        
        AVAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:combinedPath] options:nil];
        
        AVAssetTrack *clipVideoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
        
        //create a video composition and preset some settings
        AVMutableVideoComposition* videoComposition = [AVMutableVideoComposition videoComposition];
        videoComposition.frameDuration = CMTimeMake(1, 30);
        //here we are setting its render size to its height x height (Square)
        videoComposition.renderSize = CGSizeMake(clipVideoTrack.naturalSize.height, clipVideoTrack.naturalSize.height);
        
        //create a video instruction
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMakeWithSeconds(60, asset.duration.timescale));
        
        AVMutableVideoCompositionLayerInstruction* transformer = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:clipVideoTrack];
        
        //Here we shift the viewing square up to the TOP of the video so we only see the top
        CGAffineTransform t1 = CGAffineTransformMakeTranslation(clipVideoTrack.naturalSize.height, 0 );
        
        //Use this code if you want the viewing square to be in the middle of the video
//        CGAffineTransform t1 = CGAffineTransformMakeTranslation(clipVideoTrack.naturalSize.height, -(clipVideoTrack.naturalSize.width - clipVideoTrack.naturalSize.height) /2 );
        
        //Make sure the square is portrait
        CGAffineTransform t2 = CGAffineTransformRotate(t1, M_PI_2);
        
        CGAffineTransform finalTransform = t2;
        [transformer setTransform:finalTransform atTime:kCMTimeZero];
        
        //add the transformer layer instructions, then add to video composition
        instruction.layerInstructions = [NSArray arrayWithObject:transformer];
        videoComposition.instructions = [NSArray arrayWithObject: instruction];
        
        //Create an Export Path to store the cropped video
        NSString *cropPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Temp/%@Cropped.mp4",TEMP_VIDEO_NAME_PREFIX]];;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[NSFileManager defaultManager] removeItemAtPath:cropPath error:nil];
        });
        
        NSURL *exportUrl = [NSURL fileURLWithPath:cropPath];
        
        //Export
        AVAssetExportSession *finalExporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetMediumQuality] ;

        finalExporter.videoComposition = videoComposition;
        finalExporter.outputURL = exportUrl;
        finalExporter.outputFileType = AVFileTypeMPEG4;
        
        __weak VNVideoCaptureViewController *weakSelf = self;
        
        [finalExporter exportAsynchronouslyWithCompletionHandler:^
         {
             dispatch_async(dispatch_get_main_queue(), ^{
                 [weakSelf.overlayView hideCombiningMsg];
                 switch ([finalExporter status]) {
                     case AVAssetExportSessionStatusFailed:
                         NSLog(@"Export failed: %@", [[finalExporter error] localizedDescription]);
                         break;
                     case AVAssetExportSessionStatusCancelled:
                         NSLog(@"Export canceled");
                         break;
                     default:
                         
                         [weakSelf pushToCoverSettingCtl];
                         
                         break;
                 }
             });
         }];
    });
}

#pragma mark - VNCameraOverlayViewDelegate

- (void)doCloseCurrentController
{
    if(self.videoTotalDuration != 0) {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"" message:@"确定要放弃这段视频么？" delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"确定", nil];
        
        void (^clearVideoBlock)(NSInteger) = ^(NSInteger buttonIndex){
            if (buttonIndex == 0) {
                //do nothing...
            } else {
                [self clearTempVideos];
                [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ClearVideoClipsNotification" object:nil];
                [self dismissViewControllerAnimated:YES completion:nil];
            }
        };
        objc_setAssociatedObject(alert, @"ClearVideosAlert",
                                 clearVideoBlock, OBJC_ASSOCIATION_COPY);
        
        [alert show];
    }else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"ClearVideoClipsNotification" object:nil];
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

/**
 *  @description: clear temp videos in temp directory.
 */
- (void)clearTempVideos
{
    NSFileManager *fm = [NSFileManager defaultManager];
    
    
    NSString *filePath = [videoFilePath stringByAppendingPathComponent:@"Clips"];
    
    NSArray *arr = [fm contentsOfDirectoryAtPath:filePath error:nil];
    
    for (NSString *dir in arr) {
        [fm removeItemAtPath:[filePath stringByAppendingPathComponent:dir] error:nil];
    }
    
    filePath = [videoFilePath stringByAppendingPathComponent:@"Temp"];
    
    arr = [fm contentsOfDirectoryAtPath:filePath error:nil];
    
    for (NSString *dir in arr) {
        [fm removeItemAtPath:[filePath stringByAppendingPathComponent:dir] error:nil];
    }

}

- (void)doChangeTorchStatusTo:(BOOL)isOn
{
    if (isOn) {
        [self.videoInput.device setTorchMode:AVCaptureTorchModeOn];
    }else {
        [self.videoInput.device setTorchMode:AVCaptureTorchModeOff];
    }
}

- (AVCaptureDevice *)backFacingCamera {

    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionBack)
        {
            captureDevice = device;
            break;
        }
    }

    [captureDevice lockForConfiguration:nil];
    
    return captureDevice;
}

- (AVCaptureDevice *)frontFacingCamera {
    
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionFront)
        {
            captureDevice = device;
            break;
        }
    }
    
    return captureDevice;
}

/**
 *  @description: change camera device. (frong or rear.)
 *
 *  @param isRear : declares which kind of camera device to change to.
 */
- (void)doChangeDeviceTo:(BOOL)isRear
{
    [self.captureSession removeInput:self.videoInput];

    if (isRear) {

        self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:[self backFacingCamera] error:nil];
        [self.overlayView setTorchBtnHidden:NO];
    }else {
        
        
        self.videoInput = [AVCaptureDeviceInput deviceInputWithDevice:[self frontFacingCamera] error:nil];

        [self.overlayView setTorchBtnHidden:YES];
    }
    [self.captureSession addInput:self.videoInput];

}

/**
 *  @description: delecte the newest video clip.
 */
- (void)doDeleteCurrentVideo
{
    //删除当前片段
    
    NSString *currVideoPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Clips/%@%d.mov",TEMP_VIDEO_NAME_PREFIX,self.videoPieceCount]];
    
    NSError *err;
    [[NSFileManager defaultManager] removeItemAtPath:currVideoPath error:&err];
    if (!err) {
        [self.videoTimePointArr removeLastObject];
        
        self.videoTotalDuration = [[self.videoTimePointArr lastObject] floatValue];
        
        self.videoPieceCount--;
        if (self.videoPieceCount == 0) {
            [self.overlayView setTrashBtnEnabled:NO];
        }
        [self.videoPathArr removeLastObject];
        
        [self.overlayView setProgressTimeArr:self.videoTimePointArr];
        
        CGFloat percent = self.videoTotalDuration / 30.0 ;
        
        [_overlayView updateProgressViewToPercentage:percent];
        
        if (self.videoTotalDuration < MIN_VIDEO_DURATION) {
            [self.overlayView setAlbumAndSubmitBtnStatus:NO];
        }else {
            [self.overlayView setAlbumAndSubmitBtnStatus:YES];
        }
    }
}

/**
 *  @description: begin current video capturing.
 */
- (void)doStartNewVideoRecord
{
//    [self.overlayView setProgressViewBlinking:NO];
    
    NSString *currVideoPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Clips/%@%d.mov",TEMP_VIDEO_NAME_PREFIX,self.videoPieceCount+1]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:currVideoPath]) {
        
        [[NSFileManager defaultManager] removeItemAtPath:currVideoPath error:nil];
    }
    
    [self.movieOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:currVideoPath] recordingDelegate:self];
}

/**
 *  @description: end current video capture.
 */
- (void)doEndCurVideo
{
//    [self.overlayView setProgressViewBlinking:YES];
    
    if ([_durationTimer isValid]) {
        [_durationTimer invalidate];
        _durationTimer = nil;
    }
    
    if ([self.movieOutput isRecording]) {
        [self.movieOutput stopRecording];
    }
}

/**
 *  @description: combine and crop video clips.
 */
- (void)doSubmitWholeVideo
{
    if (self.videoTotalDuration >= MIN_VIDEO_DURATION) {
        
        [self.overlayView showCombiningMsg];
        
        if (self.videoPieceCount == 1) {
            [self cropSingleVideo];
        }else {
            [self combineAndCropSingleVideo];
        }
    }
}

- (void) pushToCoverSettingCtl
{
    NSString *cropPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Temp/%@Cropped.mp4",TEMP_VIDEO_NAME_PREFIX]];
    VNVideoCustomizationController *coverSettingCtl = [[VNVideoCustomizationController alloc] init];
    coverSettingCtl.videoPath = cropPath;
    [self.navigationController pushViewController:coverSettingCtl animated:YES];
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    
    void (^clearVideoBlock)(NSInteger) = objc_getAssociatedObject(alertView, @"ClearVideosAlert");
    
    clearVideoBlock(buttonIndex);
    
    objc_removeAssociatedObjects(alertView);
    
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error
{

    BOOL recordedSuccessfully = YES;
    
    if ([error code] != noErr)
    {
        // A problem occurred: Find out if the recording was successful.
        id value = [[error userInfo] objectForKey:AVErrorRecordingSuccessfullyFinishedKey];
        if (value)
            recordedSuccessfully = [value boolValue];
        // Logging the problem anyway:
        NSLog(@"A problem occurred while recording: %@", error);
    }
    if (recordedSuccessfully) {
        
        //record videos' path & save current video to temp directory for later use.
        NSString *currVideoPath = [videoFilePath stringByAppendingPathComponent:[NSString stringWithFormat:@"Clips/%@%d.mov",TEMP_VIDEO_NAME_PREFIX,self.videoPieceCount+1]];
        [self.videoPathArr addObject:currVideoPath];
        
        self.videoPieceCount++;
        if (self.videoPieceCount > 0)
            [self.overlayView setTrashBtnEnabled:YES];
        
        [self.videoTimePointArr addObject:[NSNumber numberWithFloat:self.videoTotalDuration]];
        
        [self.overlayView setProgressTimeArr:self.videoTimePointArr];
        
        //get current video file duration.
        //video duration array stores video files' duration data, for process bar
        
        if (self.videoTotalDuration >= MAX_VIDEO_DURATION) {
            [self doSubmitWholeVideo];
        }
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    _durationTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(refreshVideoDuration:) userInfo:nil repeats:YES];
    
    [_durationTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    
}

@end
