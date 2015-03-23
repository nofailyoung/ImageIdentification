//
//  ImageTargetsEAGLView.h
//  ImageIdentification
//
//  Created by 周俊杰 on 15/3/19.
//  Copyright (c) 2015年 北京金溪欣网络科技有限公司. All rights reserved.
//

#import <UIKit/UIKit.h>

#import <UIGLViewProtocol.h>

#import "Texture.h"
#import "SampleApplication3DModel.h"
#import "SampleGLResourceHandler.h"
#import "SampleApplicationSession.h"

@interface ImageTargetsEAGLView : UIView <UIGLViewProtocol, SampleGLResourceHandler>
- (id)initWithFrame:(CGRect)frame appSession:(SampleApplicationSession *) app;
- (bool) handleTouchPoint:(CGPoint) touchPoint;
@end
