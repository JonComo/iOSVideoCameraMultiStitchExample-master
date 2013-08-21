//
// Copyright (c) 2013 Jon Como
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "SRClip.h"

@class SRSequencer;

typedef void (^ErrorHandlingBlock)(NSError *error);

@protocol SRSequencerDelegate <NSObject>

@optional
-(void)sequencer:(SRSequencer *)sequencer addedClip:(SRClip *)clip;

@end

@interface SRSequencer : NSObject <AVCaptureFileOutputRecordingDelegate>


@property (nonatomic, weak) id delegate;

@property (strong, readonly) AVCaptureSession *captureSession;

@property (assign, readonly) bool isPaused;
@property (assign, readwrite) float maxDuration;
@property (copy, readwrite) ErrorHandlingBlock asyncErrorHandler;
@property (nonatomic, strong) NSMutableArray *clips;
@property (nonatomic, weak) UICollectionView *collectionViewClips;

-(id)initWithDelegate:(id <SRSequencerDelegate> )managerDelegate;

- (void)setupSessionWithPreset:(NSString *)preset withCaptureDevice:(AVCaptureDevicePosition)cd withTorchMode:(AVCaptureTorchMode)tm withError:(NSError **)error;

- (void)startRecording;
- (void)pauseRecording;
- (void)resumeRecording;
- (void)flipCamera;

- (void)reset;

- (void)finalizeRecordingToFile:(NSURL *)finalVideoLocationURL withVideoSize:(CGSize)videoSize withPreset:(NSString *)preset withCompletionHandler:(void (^)(NSError *error))completionHandler;

- (CMTime)totalRecordingDuration;

//Clip Modifications

-(void)duplicateClipAtIndex:(NSInteger)index;

@end
