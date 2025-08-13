import argparse
import csv
import os
from pathlib import Path

from PIL import Image

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--images_root', default='./02-evidence/redacted/E-001-GooglePhotos-selected')
    parser.add_argument('--out_csv', default='./04-logs/vision-scores.csv')
    parser.add_argument('--model', default='ViT-B-32')
    parser.add_argument('--pretrained', default='openai')
    args = parser.parse_args()

    # Lazy import to avoid import cost if not used
    import torch
    import open_clip

    device = 'cpu'
    model, _, preprocess = open_clip.create_model_and_transforms(args.model, pretrained=args.pretrained, device=device)
    tokenizer = open_clip.get_tokenizer(args.model)

    text_labels = [
        ('FakeIDs', 'a photo of a driver license or id card with name, date of birth, class and expiration'),
        ('DrugPayments', 'a screenshot of a payment receipt like cash app, zelle, venmo or western union'),
        ('LocationScreenshots', 'a screenshot of a map or location from google maps or apple maps'),
        ('Conversations', 'a screenshot of a chat conversation or messages thread'),
        ('BackgroundDocs', 'a scanned document related to background check or employment alias or e-verify'),
    ]
    texts = tokenizer([t for _, t in text_labels]).to(device)
    with torch.no_grad():
        text_features = model.encode_text(texts)
        text_features /= text_features.norm(dim=-1, keepdim=True)

    rows = []
    images = []
    root = Path(args.images_root)
    if not root.exists():
        print(f"Images root not found: {root}")
        return
    for p in root.rglob('*'):
        if p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'} and p.is_file():
            images.append(p)

    for img_path in sorted(images):
        try:
            with Image.open(img_path) as img:
                image = preprocess(img.convert('RGB')).unsqueeze(0).to(device)
                with torch.no_grad():
                    image_features = model.encode_image(image)
                    image_features /= image_features.norm(dim=-1, keepdim=True)
                    # cosine similarity
                    sims = (image_features @ text_features.T).squeeze(0).tolist()
            best_idx = int(max(range(len(sims)), key=lambda i: sims[i]))
            best_label = text_labels[best_idx][0]
            row = {
                'FilePath': str(img_path),
                'FileName': img_path.name,
                'PredictedCategory': best_label,
            }
            for i, (label, _) in enumerate(text_labels):
                row[f'Score_{label}'] = f"{sims[i]:.4f}"
            rows.append(row)
        except Exception as e:
            print(f"Error processing {img_path}: {e}")
            continue

    os.makedirs(Path(args.out_csv).parent, exist_ok=True)
    with open(args.out_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else ['FilePath','FileName','PredictedCategory'])
        writer.writeheader()
        for r in rows:
            writer.writerow(r)

    print(f"Wrote vision scores → {args.out_csv} ({len(rows)} files)")

if __name__ == '__main__':
    main()


