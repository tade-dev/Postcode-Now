# PostcodeNow

PostcodeNow is a one-shot iOS app for the nearest UK postcode. You open it, the code settles, the screen takes on a place colour, and you share or copy it.

The repository is **Postcode-Now**. The app name is **PostcodeNow**.

## Sequence

1. Locate, with a pulse while Core Location finds you.
2. The outcode settles, then the incode.
3. The screen washes to a studio colour for that outcode.
4. **Share Postcode** opens the system share sheet. **Copy Postcode** copies the code.

The label is always “Nearest postcode”. Northern Ireland (`BT`) is not covered. If the fix is approximate, PostcodeNow says so and still lets you share. If the lookup fails and this session already has a postcode, that last code stays on screen as “May be outdated”.

Lookup uses [postcodes.io](https://api.postcodes.io) over HTTPS. No API key.

## Open in Xcode

Xcode 15 or later, iOS 17+. Open `PostcodeNow.xcodeproj` and run the PostcodeNow scheme. Portrait only.

## Tests

Postcode parsing, the place palette, share text, and the postcodes.io client live in the `PostcodeNowCore` package:

```sh
swift test
```

## License

MIT © Akintade Oluwaseun
