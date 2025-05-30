import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info/device_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
 import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
  // Initialiser Google Mobile Ads SDK
  await MobileAds.instance.initialize();
  await FlutterDownloader.initialize(
    debug: true, // Set to false in production
    // You can also add `ignoreSsl: true` if you encounter SSL issues, but be cautious.
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Added const constructor

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Status Saver', // More descriptive title
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue, // Consistent AppBar color
          foregroundColor: Colors.white, // White icons and text on AppBar
        ),
      ),
      home: const WhatsAppStatusScreen(), // Added const
      debugShowCheckedModeBanner: false,
    );
  }
}

class WhatsAppStatusScreen extends StatefulWidget {
  const WhatsAppStatusScreen({super.key}); // Added const constructor

  @override
  _WhatsAppStatusScreenState createState() => _WhatsAppStatusScreenState();
}

class _WhatsAppStatusScreenState extends State<WhatsAppStatusScreen> {
  List<File> _videoFiles = [];
  List<File> _imageFiles = [];
  bool _isLoading = false;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    // _startNewGame();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _checkAndRequestStoragePermission();
    await _loadWhatsAppStatuses();
  }

  /// Checks and requests storage permissions based on Android version.
  Future<void> _checkAndRequestStoragePermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      PermissionStatus status;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13 (API 33) and above
        status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
      } else {
        // Android 12 (API 32) and below
        status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      }

      if (!status.isGranted) {
        if (mounted) {
          _showPermissionDialog();
        }
      }
    }
  }

  /// Shows a dialog prompting the user to enable permissions in settings.
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'Storage permission has been permanently denied. Please enable it in settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(ctx).pop();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Attempts to find the WhatsApp Statuses directory.
  /// Handles various common paths for robustness.
  Future<Directory?> _getWhatsAppStatusDirectory() async {
    try {
      final possiblePaths = [
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses', // Newer Android path
        '/storage/emulated/0/WhatsApp/Media/.Statuses', // Common older path
        '/sdcard/WhatsApp/Media/.Statuses',
        '/storage/sdcard0/WhatsApp/Media/.Statuses',
      ];

      for (String path in possiblePaths) {
        final dir = Directory(path);
        if (await dir.exists()) {
          return dir;
        }
      }

      // Fallback for older Android versions or less common setups
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final whatsappPath = '${externalDir.path.split('Android')[0]}WhatsApp/Media/.Statuses';
        final dir = Directory(whatsappPath);
        if (await dir.exists()) {
          return dir;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error finding WhatsApp directory: $e');
      return null;
    }
  }

  /// Loads WhatsApp statuses (images and videos) from the found directory.
  Future<void> _loadWhatsAppStatuses() async {
    if (!mounted) return; // Check if the widget is still mounted
    setState(() => _isLoading = true);

    try {
      final directory = await _getWhatsAppStatusDirectory();
      if (directory != null) {
        final files = await directory.list().where((file) {
          final path = file.path.toLowerCase();
          return path.endsWith('.mp4') || path.endsWith('.jpg') || path.endsWith('.png');
        }).map((file) => File(file.path)).toList();

        if (mounted) {
          setState(() {
            _videoFiles = files.where((f) => f.path.endsWith('.mp4')).toList();
            _imageFiles = files.where((f) => !f.path.endsWith('.mp4')).toList();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('WhatsApp folder not found or accessible.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading statuses: ${e.toString()}')),
        );
      }
    }
  }

  /// Saves the given media file (video or image) to the gallery.
  Future<void> _saveMedia(File file) async {
    try {
          _startNewGame();
      final isVideo = file.path.endsWith('.mp4');
      bool? success;

      if (isVideo) {
        success = await GallerySaver.saveVideo(file.path, albumName: 'WhatsApp Statuses');
      } else {
        success = await GallerySaver.saveImage(file.path, albumName: 'WhatsApp Statuses');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  (success ?? false) ? 'Saved to gallery!' : 'Failed to save media.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving media: ${e.toString()}')),
        );
      }
    }


  }

  /// Initializes and plays the given video file using Chewie.
  void _playVideo(File file) {
    _videoController?.dispose();
    _chewieController?.dispose();
    _startNewGame();
    _videoController = VideoPlayerController.file(file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _chewieController = ChewieController(
              videoPlayerController: _videoController!,
              autoPlay: true,
              looping: true,
              aspectRatio: _videoController!.value.aspectRatio,
              // Optional: Add a custom progress indicator if desired
              // progressIndicatorAndBottomTools: [
              //   const ChewieProgressColors(
              //     playedColor: Colors.red,
              //     handleColor: Colors.blue,
              //     bufferedColor: Colors.lightBlue,
              //     backgroundColor: Colors.grey,
              //   ),
              // ],
            );
          });
          // Show video in a dialog or a new screen
          showDialog(
            context: context,
            builder: (context) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                children: [
                  Center(
                    child: _chewieController != null &&
                            _chewieController!.videoPlayerController.value.isInitialized
                        ? Chewie(controller: _chewieController!)
                        : const CircularProgressIndicator(),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ).then((_) {
            // Dispose controllers when dialog is closed
            _videoController?.dispose();
            _chewieController?.dispose();
            _videoController = null;
            _chewieController = null;
          });
        }
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error playing video: $error')),
          );
        }
      });
  }

  /// Generates a thumbnail for a given video file.
  Future<Uint8List?> _getVideoThumbnail(File videoFile) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        quality: 50,
        maxWidth: 200, // Reduced size for grid view
      );
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
        _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  /// Builds a single media item (image or video) for the grid.
  Widget _buildMediaItem(File file, bool isVideo) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4, // Added elevation for better visual
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Rounded corners
      child: Stack(
        fit: StackFit.expand, // Make stack fill the card
        children: [
          if (isVideo)
            FutureBuilder<Uint8List?>(
              future: _getVideoThumbnail(file),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                } else if (snapshot.hasError) {
                  return const Center(child: Icon(Icons.broken_image, size: 40));
                }
                return const Center(child: CircularProgressIndicator());
              },
            )
          else
            Image.file(file, fit: BoxFit.cover),
          if (isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill, size: 50, color: Colors.white70),
            ),
          Positioned(
            bottom: 8,
            right: 8,
            child: FloatingActionButton(
              mini: true,
              heroTag: UniqueKey(), // Use UniqueKey for heroTag
              onPressed: () => _saveMedia(file),
              backgroundColor: Colors.blueAccent, // Brighter color
              child: const Icon(Icons.download, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }


  // Publicités interstitielles
  InterstitialAd? _interstitialAd;
  final _gameLength = 5; // Temps en secondes avant de montrer l'interstitielle
  late var _counter = _gameLength;

  // L'ID de l'unité d'annonce (pour l'interstitielle)
  final String _adUnitIdd = Platform.isAndroid
      ? 'ca-app-pub-8882238368661853/3807888615' // Exemple ID Android
      : 'ca-app-pub-8882238368661853/3807888615'; // Exemple ID iOS
      // Remplacez ces IDs par vos vrais IDs AdMob en production !

  void _startNewGame() {
    setState(() => _counter = _gameLength);
    _loadInterstitialAd();
    _startTimer();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _adUnitIdd,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdShowedFullScreenContent: (ad) {},
              onAdImpression: (ad) {},
              onAdFailedToShowFullScreenContent: (ad, err) {
                ad.dispose();
              },
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
              },
              onAdClicked: (ad) {});
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('InterstitialAd failed to load: $error');
        },
      ),
    );
  }

  void _startTimer() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _counter--);
      if (_counter == 0) {
        _interstitialAd?.show();
        timer.cancel();
        // Optionnel: Recharger une nouvelle pub après l'affichage
        // _startNewGame();
      }
    });
  }

  // Publicités bannière
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  // L'ID de l'unité d'annonce (pour la bannière)
  final String _adUnitId = Platform.isAndroid
      ? 'ca-app-pub-8882238368661853/1006164136' // Exemple ID Android
      : 'ca-app-pub-8882238368661853/1006164136'; // Exemple ID iOS
      // Remplacez ces IDs par vos vrais IDs AdMob en production !

 void _loadBannerAd() async {
    // Obtenir la taille adaptative pour la bannière
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
        MediaQuery.of(context).size.width.truncate());

    if (size == null) {
      debugPrint('Unable to get a suitable banner ad size.');
      return;
    }

    BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAd failed to load: $err');
          ad.dispose();
        },
        onAdOpened: (Ad ad) => debugPrint('BannerAd opened.'),
        onAdClosed: (Ad ad) => debugPrint('BannerAd closed.'),
        onAdImpression: (Ad ad) => debugPrint('BannerAd impression.'),
      ),
    ).load();
  }



  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isBannerAdLoaded) { // Assure que la bannière n'est chargée qu'une fois
      _loadBannerAd();
    }
  }

 

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WhatsApp Status Saver'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadWhatsAppStatuses,
              tooltip: 'Refresh Statuses', // Added tooltip
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.video_library), text: 'Videos'), // Added text
              Tab(icon: Icon(Icons.photo), text: 'Images'), // Added text
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // Video Tab
                  _videoFiles.isEmpty
                      ? const Center(child: Text('No videos found.'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.75, // Adjust aspect ratio for better display
                          ),
                          itemCount: _videoFiles.length,
                          itemBuilder: (context, index) {
                            final file = _videoFiles[index];
                            return GestureDetector(
                              onTap: () => _playVideo(file),
                              child: _buildMediaItem(file, true),
                            );
                          },
                        ),

                  // Photo Tab
                  _imageFiles.isEmpty
                      ? const Center(child: Text('No images found.'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.75, // Adjust aspect ratio
                          ),
                          itemCount: _imageFiles.length,
                          itemBuilder: (context, index) {
                            final file = _imageFiles[index];
                            return GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.black, // Dark background for images
                                  insetPadding: EdgeInsets.zero,
                                  child: InteractiveViewer(
                                    child: Image.file(file, fit: BoxFit.contain), // Use contain for full image
                                  ),
                                ),
                              ),
                              child: _buildMediaItem(file, false),
                            );
                          },
                        ),
                ],
              ),
               bottomNavigationBar: _bannerAd != null && _isBannerAdLoaded
          ? SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            )
          : null,
      ),
        // Publicités interstitielles


    
 
    );
  }
}