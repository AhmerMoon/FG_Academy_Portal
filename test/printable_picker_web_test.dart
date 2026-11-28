@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:academy_portal/utils/printable_file_actions_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

@JS('eval')
external JSAny? evaluate(JSString code);

void main() {
  setUpAll(() {
    // Keep the test in-browser: simulate choosing a file without an OS dialog.
    evaluate(
      '''
      globalThis.__printableOriginalClick = HTMLInputElement.prototype.click;
      HTMLInputElement.prototype.click = function() {
        if (this.type !== 'file') globalThis.__printableOriginalClick.call(this);
      };
    '''
          .toJS,
    );
  });
  tearDownAll(() {
    evaluate(
      '''
      HTMLInputElement.prototype.click = globalThis.__printableOriginalClick;
      delete globalThis.__printableOriginalClick;
    '''
          .toJS,
    );
  });
  test('returning focus cannot cancel a delayed file selection', () async {
    final selection = pickPrintableFile();
    var completed = false;
    selection.then((_) => completed = true);
    web.window.dispatchEvent(web.Event('focus'));
    // Reproduce the browser returning focus before its change event.
    await Future<void>.delayed(const Duration(milliseconds: 750));
    expect(completed, isFalse);

    final input =
        web.document.querySelector('input[data-printable-picker]')!
            as web.HTMLInputElement;
    final bytes = Uint8List.fromList([37, 80, 68, 70, 45]);
    final transfer = web.DataTransfer();
    transfer.items.add(
      web.File(
        [bytes.toJS].toJS,
        'paper.pdf',
        web.FilePropertyBag(type: 'application/pdf'),
      ),
    );
    input.files = transfer.files;
    input.dispatchEvent(web.Event('change'));

    final file = await selection.timeout(const Duration(seconds: 3));
    expect(file?.name, 'paper.pdf');
    expect(await file!.length(), bytes.length);
    expect(await file.readAsBytes(), bytes);
  });

  test('actual browser cancellation completes normally', () async {
    final selection = pickPrintableFile();
    final input =
        web.document.querySelector('input[data-printable-picker]')!
            as web.HTMLInputElement;
    input.dispatchEvent(web.Event('cancel'));
    expect(await selection.timeout(const Duration(seconds: 3)), isNull);
  });
}
