# Convert ProRAW(DNG) to JPEG on iOS devices

On iOS, there are already several ways to convert ProRAW images to jpg images, such as using shortcut. However, using shortcut to convert will cause the HDR gain map in the image to be lost, resulting in a loss of HDR effect in the converted image.

This simple demo preserves the gain map when converting ProRAW photos to JPEG photos. It works as follows:

For **edited** ProRAW images, since a full-size JPEG preview is stored in the Gallery, the code will extract this JPEG preview image.

For **unmodified** ProRAW images, the app will extract the embedded full-size preview from the DNG file. An alternative is to use ImageIO related Api to convert DNG to JPEG and migrate the gain map. The appearance of the images produced by these two methods are almost identical.