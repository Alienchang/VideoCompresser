//
//  KMVideoTool.h
//  AIBasicModule
//
//  Created by 刘畅 on 2022/4/12.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KMVideoTool : NSObject
+ (UIImage *)thumbImage:(NSURL *)videoURL;
+ (NSInteger)durationWithvideoURL:(NSURL *)videoURL;
+ (void)compressWithVideoURL:(NSURL *)videoURL
                   outputURL:(NSURL *)outputURL
                         fps:(NSInteger)fps             // 24
                     bitRate:(NSInteger)bitRate         // 200 * 8 * 1024
              dimensionScale:(CGFloat)dimensionScale
                  completion:(void(^)(BOOL success))completion;
@end

NS_ASSUME_NONNULL_END
