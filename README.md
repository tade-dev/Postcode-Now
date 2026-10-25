# PostcodeNow

PostcodeNow is a one-shot iOS app for the nearest UK postcode. You open it, the code settles, the screen takes on a place colour, and you share or copy it.

The repository is **Postcode-Now**. The app name is **PostcodeNow**.

## Sequence

1. Scanning rings while Core Location finds you — they loop for as long as it takes.
2. The rings collapse into a lock, stretch into a line, and the postcode rises out of it.
3. The place colour floods out from the code itself.
4. **Share Postcode** opens the system share sheet. **Copy Postcode** copies the code.

A tap during the reveal jumps straight to the settled state. Reduce Motion
shows the settled state from the start.

Every UK outcode has its own colour, derived from the outcode itself and
forced into a contrast-safe band — so a postcode always looks the same, and
neighbouring postcodes look different.

## Open in Xcode

Xcode 15 or later, iOS 17+. Open `PostcodeNow.xcodeproj` and run the PostcodeNow scheme. Portrait only.

## Tests

Postcode parsing, the place palette, the reveal timeline, share text, and the
postcodes.io client live in the `PostcodeNowCore` package:

```sh
swift test
```

## License

MIT © Akintade Oluwaseun
