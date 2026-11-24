// ignore_for_file: public_member_api_docs, sort_constructors_first
class AdditionalWeatherData {
  final String precipitation;
  final double uvi;
  final int clouds;
  final int? humidity;
  final double? windSpeed;

  AdditionalWeatherData({
    required this.precipitation,
    required this.uvi,
    required this.clouds,
    dynamic humidity,
    this.windSpeed,
  }) : humidity = humidity == null
            ? null
            : (humidity is int
                ? humidity
                : int.tryParse(humidity.toString()));

  factory AdditionalWeatherData.fromJson(Map<String, dynamic> json) {
    final precipData = json['daily'][0]['pop'];
    final precip = (precipData * 100).toStringAsFixed(0);
    return AdditionalWeatherData(
      precipitation: precip,
      uvi: (json['daily'][0]['uvi']).toDouble(),
      clouds: json['daily'][0]['clouds'] ?? 0,
    );
  }
}
