//
// Copyright (c) 2013 Carson McDonald
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
// and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions
// of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
// TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.
//

#import "RecordingViewController.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <MediaPlayer/MediaPlayer.h>

#import "LXReorderableCollectionViewFlowLayout.h"

#import "MBProgressHUD.h"

#import "SRSequencer.h"

@interface RecordingViewController (Private) <SRSequencerDelegate, UICollectionViewDelegateFlowLayout>

- (void)updateProgress:(NSTimer *)timer;
- (void)saveOutputToAssetLibrary:(NSURL *)outputFileURL completionBlock:(void (^)(NSError *error))completed;

@end

// Maximum and minumum length to record in seconds
#define MAX_RECORDING_LENGTH 600.0
#define MIN_RECORDING_LENGTH 1.0

// Set the recording preset to use
#define CAPTURE_SESSION_PRESET AVCaptureSessionPreset640x480

// Set the input device to use when first starting
#define INITIAL_CAPTURE_DEVICE_POSITION AVCaptureDevicePositionBack

// Set the initial torch mode
#define INITIAL_TORCH_MODE AVCaptureTorchModeOff

@implementation RecordingViewController
{
    SRSequencer *sequencer;
    
    AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
    
    NSTimer *progressUpdateTimer;
    
    __weak IBOutlet UICollectionView *collectionViewClips;
    
    LXReorderableCollectionViewFlowLayout *layout;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.videoRecrodingProgress.alpha = 0;
    
    sequencer = [[SRSequencer alloc] initWithDelegate:self];
    sequencer.collectionViewClips = collectionViewClips;
    
    layout = [[LXReorderableCollectionViewFlowLayout alloc] init];
    [layout setMinimumInteritemSpacing:0];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    [collectionViewClips setCollectionViewLayout:layout];
    
    collectionViewClips.delegate = self;
    
    sequencer.maxDuration = MAX_RECORDING_LENGTH;
    sequencer.asyncErrorHandler = ^(NSError *error) {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    };
    
    NSError *error;
    [sequencer setupSessionWithPreset:CAPTURE_SESSION_PRESET
                                  withCaptureDevice:INITIAL_CAPTURE_DEVICE_POSITION
                                      withTorchMode:INITIAL_TORCH_MODE
                                          withError:&error];
    
    
    if(error)
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    }
    else
    {
        captureVideoPreviewLayer = [AVCaptureVideoPreviewLayer layerWithSession:sequencer.captureSession];
        
        self.videoPreviewView.layer.masksToBounds = YES;
        captureVideoPreviewLayer.frame = self.videoPreviewView.bounds;
        
        captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        
        [self.videoPreviewView.layer insertSublayer:captureVideoPreviewLayer below:self.videoPreviewView.layer.sublayers[0]];
        
        // Start the session. This is done asychronously because startRunning doesn't return until the session is running.
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [sequencer.captureSession startRunning];
        });
        
        self.saveButton.hidden = YES;
    }
}

- (void)updateProgress:(NSTimer *)timer
{
    CMTime duration = [sequencer totalRecordingDuration];
    
    self.videoRecrodingProgress.progress = CMTimeGetSeconds(duration) / MAX_RECORDING_LENGTH;
    
    if(CMTimeGetSeconds(duration) >= MIN_RECORDING_LENGTH)
    {
        self.saveButton.hidden = NO;
    }
    
    if(CMTimeGetSeconds(duration) >= MAX_RECORDING_LENGTH)
    {
        self.recordButton.enabled = NO;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    captureVideoPreviewLayer.frame = self.videoPreviewView.bounds;
    
    if ([sequencer.captureSession isInterrupted])
    {
        [sequencer.captureSession startRunning];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark Record button

- (IBAction)cancelAction:(id)sender
{
    self.saveButton.hidden = YES;
    
    self.videoRecrodingProgress.progress = 0.0;

    [sequencer reset];
}

- (IBAction)recordTouchDown:(id)sender
{
    progressUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                           target:self
                                                         selector:@selector(updateProgress:)
                                                         userInfo:nil
                                                          repeats:YES];
    
    if(sequencer.isPaused){
        [sequencer resumeRecording];
    }else{
        [sequencer startRecording];
    }
}

- (IBAction)recordTouchCancel:(id)sender
{
    [progressUpdateTimer invalidate];
    [sequencer pauseRecording];
}

- (IBAction)recordTouchUp:(id)sender
{
    [progressUpdateTimer invalidate];
    [sequencer pauseRecording];
}

- (IBAction)flipCamera:(id)sender
{
    [sequencer flipCamera];
}

- (IBAction)saveRecording:(id)sender
{
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.videoPreviewView animated:YES];
    [hud setMode:MBProgressHUDModeIndeterminate];
    [hud setLabelText:@"Rendering"];
    
    self.saveButton.hidden = YES;
    
    NSURL *finalOutputFileURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@%@-%ld.mp4", NSTemporaryDirectory(), @"final", (long)[[NSDate date] timeIntervalSince1970]]];
    
    [sequencer finalizeRecordingToFile:finalOutputFileURL
                                       withVideoSize:CGSizeMake(500, 500)
                                          withPreset:AVAssetExportPreset640x480
                                            withCompletionHandler:^(NSError *error)
    {
        [MBProgressHUD hideAllHUDsForView:self.videoPreviewView animated:YES];
        
        if(error)
        {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error" message:error.domain delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alertView show];
        }
        else
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                self.recordButton.enabled = YES;
                self.saveButton.hidden = NO;
                
                MPMoviePlayerViewController *player = [[MPMoviePlayerViewController alloc] initWithContentURL:finalOutputFileURL];
                [self presentViewController:player animated:YES completion:nil];
            });
            
            /*
            [self saveOutputToAssetLibrary:finalOutputFileURL completionBlock:^(NSError *saveError) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Done" message:@"The video has been saved to your camera roll." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
                    [alertView show];
                    
                    if ([[NSFileManager defaultManager] fileExistsAtPath:[finalOutputFileURL path]])
                        [[NSFileManager defaultManager] removeItemAtURL:finalOutputFileURL error:nil];
                    
                    self.videoRecrodingProgress.progress = 0.0;
                    self.recordButton.enabled = YES;
                });
            }];
             */
        }
        
    }];
}

- (IBAction)duplicate:(id)sender
{
    [sequencer duplicateClipAtIndex:MAX(0,sequencer.clips.count-1)];
}

- (void)saveOutputToAssetLibrary:(NSURL *)outputFileURL completionBlock:(void (^)(NSError *error))completed
{
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    [library writeVideoAtPathToSavedPhotosAlbum:outputFileURL completionBlock:^(NSURL *assetURL, NSError *error) {
        completed(error);
    }];
}

#pragma videoCameraInputManagerDelegate

-(void)videoCameraInputManager:(SRSequencer *)manager addedClip:(SRClip *)clip
{
    [collectionViewClips reloadData];
}

#pragma UICollectionViewDelegate

-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [sequencer.clips removeObjectAtIndex:indexPath.row];
    [collectionView deleteItemsAtIndexPaths:@[indexPath]];
}

@end
