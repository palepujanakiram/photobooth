import 'dart:io';

int? currentProcessResidentBytes() => ProcessInfo.currentRss;
