#import "CTLocalization.h"
#import "THtmlViewController.h"
#import "BackButtonHandler.h"

@implementation HtmlViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.navigationItem.title = CTLocalizedString(self.pageTitle);
	self.indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	self.indicator.color = [UIColor blackColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.indicator];

	WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero];
	webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	webView.navigationDelegate = self;

	[webView loadFileURL:self.url allowingReadAccessToURL:self.url.URLByDeletingLastPathComponent];
	self.view = webView;
}

- (BOOL)navigationShouldPopOnBackButton
{
	WKWebView *webView = (WKWebView *)self.view;
	if (webView.canGoBack) {
		[webView goBack];
		return NO;
	}
	return YES;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
	[self.indicator startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	[self.indicator stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self.indicator stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self.indicator stopAnimating];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

- (id)initWithURL:(NSString *)url title:(NSString *)title;
{
	self = [super init];
	if (self != nil) {
		self.url = [[NSBundle mainBundle] URLForResource:url withExtension:@"html"];
		self.pageTitle = title;
	}
	return self;
}

@end
