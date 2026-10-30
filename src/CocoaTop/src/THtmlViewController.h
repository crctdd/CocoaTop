#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface HtmlViewController : UIViewController<WKNavigationDelegate>
@property(strong) NSURL *url;
@property(strong) NSString *pageTitle;
@property(strong) UIActivityIndicatorView *indicator;
- (id)initWithURL:(NSString *)url title:(NSString *)title;
@end
