using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using SkiaSharp;
using SkiaSharp.Skottie;

namespace Ding
{
    public enum CharacterKind
    {
        /// <summary>A Lottie animation bundled in the Characters folder.</summary>
        Lottie,
        /// <summary>The user's own picture, in %AppData%\Ding\My Characters.</summary>
        Image,
    }

    /// <summary>One of the menu's choices for who delivers a reminder.</summary>
    public sealed record Character(string Name, string Path, CharacterKind Kind)
    {
        public bool IsCustom => Kind == CharacterKind.Image;

        /// <summary>Bundled animations (alphabetically), then the user's images.</summary>
        public static IReadOnlyList<Character> All()
        {
            var list = new List<Character>();
            var folder = System.IO.Path.Combine(AppContext.BaseDirectory, "Characters");
            if (Directory.Exists(folder))
            {
                list.AddRange(Directory.GetFiles(folder, "*.json")
                    .Select(f => new Character(System.IO.Path.GetFileNameWithoutExtension(f), f, CharacterKind.Lottie))
                    .OrderBy(c => c.Name, StringComparer.OrdinalIgnoreCase));
            }
            list.AddRange(CustomCharacters.All());
            return list;
        }

        public Animation? LoadAnimation()
        {
            if (Kind != CharacterKind.Lottie) return null;
            try
            {
                return Animation.TryParse(File.ReadAllText(Path), out var animation) ? animation : null;
            }
            catch
            {
                return null;
            }
        }
    }

    /// <summary>
    /// The user's own images: imported, optionally cut out, and kept as PNGs.
    /// Subject lifting uses U²-Net (Apache 2.0), run locally with ONNX Runtime.
    /// </summary>
    public static class CustomCharacters
    {
        public static string Folder =>
            System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ding", "My Characters");

        private static string ModelPath =>
            System.IO.Path.Combine(AppContext.BaseDirectory, "Assets", "Models", "u2netp.onnx");

        public static IReadOnlyList<Character> All()
        {
            if (!Directory.Exists(Folder)) return Array.Empty<Character>();
            return Directory.GetFiles(Folder, "*.png")
                .OrderBy(File.GetCreationTimeUtc)
                .Select(f => new Character(Path.GetFileNameWithoutExtension(f), f, CharacterKind.Image))
                .ToList();
        }

        /// <summary>Reads PNG, JPEG, WebP, BMP or GIF, at most 1600 px on the long side.</summary>
        public static SKBitmap? Load(string path)
        {
            try
            {
                var bitmap = SKBitmap.Decode(path);
                return bitmap is null ? null : ScaledDown(bitmap, 1600);
            }
            catch
            {
                return null;
            }
        }

        /// <summary>
        /// Lifts the main subject (person, pet, object) off its background. Returns null
        /// when no clear subject is found or the model can't run.
        /// </summary>
        public static SKBitmap? ExtractSubject(SKBitmap source)
        {
            if (!File.Exists(ModelPath)) return null;
            try
            {
                const int side = 320;
                using var session = new InferenceSession(ModelPath);
                using var small = source.Resize(new SKImageInfo(side, side, SKColorType.Rgba8888, SKAlphaType.Unpremul), SKFilterQuality.High);
                var pixels = small.Pixels;

                // U²-Net input: RGB scaled by the brightest value, then ImageNet normalisation, NCHW.
                var brightest = 1f;
                foreach (var p in pixels) brightest = Math.Max(brightest, Math.Max(p.Red, Math.Max(p.Green, p.Blue)));
                float[] mean = { 0.485f, 0.456f, 0.406f }, std = { 0.229f, 0.224f, 0.225f };
                var input = new DenseTensor<float>(new[] { 1, 3, side, side });
                for (var y = 0; y < side; y++)
                {
                    for (var x = 0; x < side; x++)
                    {
                        var p = pixels[y * side + x];
                        input[0, 0, y, x] = (p.Red / brightest - mean[0]) / std[0];
                        input[0, 1, y, x] = (p.Green / brightest - mean[1]) / std[1];
                        input[0, 2, y, x] = (p.Blue / brightest - mean[2]) / std[2];
                    }
                }

                var inputName = session.InputMetadata.Keys.First();
                using var results = session.Run(new[] { NamedOnnxValue.CreateFromTensor(inputName, input) });
                var output = results.First().AsTensor<float>();

                // Normalise the prediction to 0…255 as a mask.
                float lo = float.MaxValue, hi = float.MinValue;
                for (var i = 0; i < side * side; i++)
                {
                    var v = output.GetValue(i);
                    lo = Math.Min(lo, v);
                    hi = Math.Max(hi, v);
                }
                var range = Math.Max(hi - lo, 1e-6f);
                using var mask = new SKBitmap(new SKImageInfo(side, side, SKColorType.Gray8, SKAlphaType.Opaque));
                var maskPixels = new SKColor[side * side];
                for (var i = 0; i < side * side; i++)
                {
                    var m = (byte)Math.Clamp((output.GetValue(i) - lo) / range * 255, 0, 255);
                    maskPixels[i] = new SKColor(m, m, m);
                }
                mask.Pixels = maskPixels;
                using var fullMask = mask.Resize(new SKImageInfo(source.Width, source.Height, SKColorType.Gray8, SKAlphaType.Opaque), SKFilterQuality.High);

                var src = source.Pixels;
                var alpha = fullMask.Pixels;
                var result = new SKColor[src.Length];
                var solid = 0;
                for (var i = 0; i < src.Length; i++)
                {
                    var a = alpha[i].Red;
                    if (a > 128) solid++;
                    result[i] = src[i].WithAlpha((byte)(a * src[i].Alpha / 255));
                }
                // Nothing worth calling a subject.
                if (solid < src.Length * 0.02) return null;

                var cutout = new SKBitmap(new SKImageInfo(source.Width, source.Height, SKColorType.Rgba8888, SKAlphaType.Unpremul));
                cutout.Pixels = result;
                return cutout;
            }
            catch
            {
                return null;
            }
        }

        /// <summary>Saves the picture as a new character (trimmed, at most 640 px) and returns it.</summary>
        public static Character Save(SKBitmap image, string wantedName)
        {
            Directory.CreateDirectory(Folder);
            var name = UniqueName(wantedName);
            var path = Path.Combine(Folder, name + ".png");
            using var prepared = Trimmed(ScaledDown(image.Copy(), 640));
            using var encoded = SKImage.FromBitmap(prepared).Encode(SKEncodedImageFormat.Png, 100);
            File.WriteAllBytes(path, encoded.ToArray());
            return new Character(name, path, CharacterKind.Image);
        }

        public static void Remove(Character character)
        {
            if (!character.IsCustom) return;
            try { File.Delete(character.Path); } catch { /* already gone */ }
        }

        private static string UniqueName(string wanted)
        {
            var invalid = Path.GetInvalidFileNameChars();
            var name = new string(wanted.Trim().Select(ch => invalid.Contains(ch) ? '-' : ch).ToArray());
            if (name.Length == 0) name = "My Character";
            var taken = new HashSet<string>(Character.All().Select(c => c.Name), StringComparer.OrdinalIgnoreCase);
            var candidate = name;
            for (var n = 2; taken.Contains(candidate); n++) candidate = $"{name} {n}";
            return candidate;
        }

        private static SKBitmap ScaledDown(SKBitmap bitmap, int longest)
        {
            var current = Math.Max(bitmap.Width, bitmap.Height);
            if (current <= longest) return bitmap;
            var scale = longest / (double)current;
            var resized = bitmap.Resize(new SKImageInfo((int)(bitmap.Width * scale), (int)(bitmap.Height * scale),
                                                        SKColorType.Rgba8888, SKAlphaType.Unpremul), SKFilterQuality.High);
            bitmap.Dispose();
            return resized;
        }

        /// <summary>Crops away fully transparent edges, so the character's feet are the image's bottom.</summary>
        private static SKBitmap Trimmed(SKBitmap bitmap)
        {
            var pixels = bitmap.Pixels;
            int w = bitmap.Width, h = bitmap.Height;
            int minX = w, maxX = -1, minY = h, maxY = -1;
            for (var y = 0; y < h; y++)
            {
                for (var x = 0; x < w; x++)
                {
                    if (pixels[y * w + x].Alpha <= 8) continue;
                    minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                    minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
                }
            }
            if (maxX < minX) return bitmap;
            var subset = new SKBitmap();
            return bitmap.ExtractSubset(subset, new SKRectI(minX, minY, maxX + 1, maxY + 1)) ? subset : bitmap;
        }
    }

    /// <summary>
    /// Where the drawing actually sits inside a Lottie canvas (fractions, y downward) and
    /// which frame looks most like standing still. Characters are usually drawn mid-canvas
    /// with empty space around them, so the canvas edge is not where their feet are.
    /// </summary>
    public readonly record struct ArtBounds(double Top, double Bottom, double CenterX, double StandFrame)
    {
        public static ArtBounds Default => new(0.25, 0.75, 0.5, 0);

        public static ArtBounds Measure(Animation animation)
        {
            const int size = 160;
            using var bitmap = new SKBitmap(new SKImageInfo(size, size, SKColorType.Rgba8888, SKAlphaType.Premul));
            using var canvas = new SKCanvas(bitmap);
            var rect = SKRect.Create(size, size);

            int minRow = size, maxRow = -1, minCol = size, maxCol = -1;
            var narrowestWidth = int.MaxValue;
            // Skottie counts frames from the start of the animation: 0 … duration × fps.
            var span = animation.Duration.TotalSeconds * animation.Fps;
            var narrowestFrame = 0.0;

            for (var i = 0; i < 16; i++)
            {
                var frame = span * i / 16.0;
                canvas.Clear(SKColors.Transparent);
                animation.SeekFrame(frame);
                animation.Render(canvas, rect);
                canvas.Flush();

                int frameMin = size, frameMax = -1;
                for (var y = 0; y < size; y++)
                {
                    for (var x = 0; x < size; x++)
                    {
                        if (bitmap.GetPixel(x, y).Alpha <= 20) continue;
                        minRow = Math.Min(minRow, y); maxRow = Math.Max(maxRow, y);
                        frameMin = Math.Min(frameMin, x); frameMax = Math.Max(frameMax, x);
                    }
                }
                minCol = Math.Min(minCol, frameMin); maxCol = Math.Max(maxCol, frameMax);
                if (frameMax >= 0 && frameMax - frameMin < narrowestWidth)
                {
                    narrowestWidth = frameMax - frameMin;
                    narrowestFrame = frame;
                }
            }

            if (maxRow < 0) return Default;
            return new ArtBounds(
                Top: minRow / (double)size,
                Bottom: (maxRow + 1) / (double)size,
                CenterX: (minCol + maxCol + 1) / 2.0 / size,
                StandFrame: narrowestFrame);
        }
    }
}
