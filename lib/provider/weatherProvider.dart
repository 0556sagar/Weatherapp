import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/additionalWeatherData.dart';
import '../models/dailyWeather.dart';
import '../models/geocode.dart';
import '../models/hourlyWeather.dart';
import '../models/weather.dart';

class WeatherConditionMap {
  final String category;
  final String description;
  WeatherConditionMap(this.category, this.description);
}

WeatherConditionMap mapWmoCode(int code) {
  switch (code) {
    case 0:
      return WeatherConditionMap('clear', 'Clear sky');
    case 1:
      return WeatherConditionMap('clear', 'Mainly clear');
    case 2:
      return WeatherConditionMap('clouds', 'Partly cloudy');
    case 3:
      return WeatherConditionMap('clouds', 'Overcast');
    case 45:
    case 48:
      return WeatherConditionMap('fog', 'Foggy');
    case 51:
    case 53:
    case 55:
      return WeatherConditionMap('drizzle', 'Drizzle');
    case 56:
    case 57:
      return WeatherConditionMap('drizzle', 'Freezing drizzle');
    case 61:
    case 63:
    case 65:
      return WeatherConditionMap('rain', 'Rainy');
    case 66:
    case 67:
      return WeatherConditionMap('rain', 'Freezing rain');
    case 71:
    case 73:
    case 75:
    case 77:
      return WeatherConditionMap('snow', 'Snowy');
    case 80:
    case 81:
    case 82:
      return WeatherConditionMap('rain', 'Rain showers');
    case 85:
    case 86:
      return WeatherConditionMap('snow', 'Snow showers');
    case 95:
    case 96:
    case 99:
      return WeatherConditionMap('thunderstorm', 'Thunderstorm');
    default:
      return WeatherConditionMap('clouds', 'Cloudy');
  }
}

class WeatherProvider with ChangeNotifier {
  String apiKey = '';
  late Weather weather;
  late AdditionalWeatherData additionalWeatherData;
  LatLng? currentLocation;
  List<HourlyWeather> hourlyWeather = [];
  List<DailyWeather> dailyWeather = [];
  bool isLoading = false;
  bool isRequestError = false;
  bool isSearchError = false;
  bool isLocationServiceEnabled = false;
  LocationPermission? locationPermission;
  bool isCelsius = true;

  String get measurementUnit => isCelsius ? '°C' : '°F';

  Future<Position?> requestLocation(BuildContext context) async {
    isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    notifyListeners();

    if (!isLocationServiceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled.'),
        ),
      );
      return null;
    }

    locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied) {
      locationPermission = await Geolocator.requestPermission();
      if (locationPermission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are denied'),
          ),
        );
        return null;
      }
    }

    if (locationPermission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Location permissions are permanently denied, we cannot request permissions.'),
        ),
      );
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> getWeatherData(
    BuildContext context, {
    bool notify = false,
  }) async {
    isLoading = true;
    isRequestError = false;
    if (notify) notifyListeners();

    try {
      Position? loc = await requestLocation(context);
      if (loc != null) {
        currentLocation = LatLng(loc.latitude, loc.longitude);
      } else {
        currentLocation = const LatLng(28.6139, 77.2090);
      }
      await getCurrentWeather(currentLocation!);
      await getDailyWeather(currentLocation!);
    } catch (e) {
      isRequestError = true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> getCurrentWeather(LatLng location) async {
    final url =
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&hourly=temperature_2m,relative_humidity_2m,surface_pressure,wind_speed_10m,weather_code&daily=temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_probability_max&timezone=auto';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load weather');
    }

    final data = json.decode(response.body);
    final current = data['current_weather'];
    final hourly = data['hourly'];
    final daily = data['daily'];

    double temp = (current['temperature'] as num).toDouble();
    double wind = (current['windspeed'] as num).toDouble();
    int code = (current['weathercode'] as num).toInt();

    int humidity = 0;
    int pressure = 1013;
    if (hourly != null) {
      if (hourly['relative_humidity_2m'] != null &&
          (hourly['relative_humidity_2m'] as List).isNotEmpty) {
        humidity = (hourly['relative_humidity_2m'][0] as num).toInt();
      }
      if (hourly['surface_pressure'] != null &&
          (hourly['surface_pressure'] as List).isNotEmpty) {
        pressure = (hourly['surface_pressure'][0] as num).round();
      }
    }

    double tempMax = temp;
    double tempMin = temp;
    double uvi = 0.0;
    String precip = '0%';
    if (daily != null) {
      if (daily['temperature_2m_max'] != null &&
          (daily['temperature_2m_max'] as List).isNotEmpty) {
        tempMax = (daily['temperature_2m_max'][0] as num).toDouble();
      }
      if (daily['temperature_2m_min'] != null &&
          (daily['temperature_2m_min'] as List).isNotEmpty) {
        tempMin = (daily['temperature_2m_min'][0] as num).toDouble();
      }
      if (daily['uv_index_max'] != null &&
          (daily['uv_index_max'] as List).isNotEmpty) {
        uvi = (daily['uv_index_max'][0] as num).toDouble();
      }
      if (daily['precipitation_probability_max'] != null &&
          (daily['precipitation_probability_max'] as List).isNotEmpty) {
        precip = '${daily['precipitation_probability_max'][0]}%';
      }
    }

    var condition = mapWmoCode(code);

    String cityName = 'Current Location';
    String countryCode = 'IN';
    try {
      if (weather.city.isNotEmpty && weather.city != 'Search Site') {
        cityName = weather.city;
      }
    } catch (_) {}

    weather = Weather(
      temp: temp,
      tempMax: tempMax,
      tempMin: tempMin,
      lat: location.latitude,
      long: location.longitude,
      feelsLike: temp,
      pressure: pressure,
      description: condition.description,
      weatherCategory: condition.category,
      humidity: humidity,
      windSpeed: wind,
      city: cityName,
      countryCode: countryCode,
    );

    additionalWeatherData = AdditionalWeatherData(
      precipitation: precip,
      uvi: uvi,
      clouds: 0,
    );

    hourlyWeather = [];
    if (hourly != null && hourly['time'] != null) {
      final times = hourly['time'] as List;
      final temps = hourly['temperature_2m'] as List;
      final codes = hourly['weather_code'] as List;
      int count = times.length > 24 ? 24 : times.length;
      for (int i = 0; i < count; i++) {
        int hCode = (codes[i] as num).toInt();
        var hCond = mapWmoCode(hCode);
        hourlyWeather.add(HourlyWeather(
          temp: (temps[i] as num).toDouble(),
          weatherCategory: hCond.category,
          condition: hCond.description,
          date: DateTime.parse(times[i].toString()),
        ));
      }
    }
  }

  Future<void> getDailyWeather(LatLng location) async {
    final url =
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&daily=weather_code,temperature_2m_max,temperature_2m_min,uv_index_max,precipitation_probability_max&timezone=auto';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to load daily weather');
    }

    final data = json.decode(response.body);
    final daily = data['daily'];

    dailyWeather = [];
    if (daily != null && daily['time'] != null) {
      final dates = daily['time'] as List;
      final maxTemps = daily['temperature_2m_max'] as List;
      final minTemps = daily['temperature_2m_min'] as List;
      final codes = daily['weather_code'] as List;
      final uvis = daily['uv_index_max'] as List?;
      final precips = daily['precipitation_probability_max'] as List?;

      for (int i = 0; i < dates.length; i++) {
        int dCode = (codes[i] as num).toInt();
        var dCond = mapWmoCode(dCode);
        double maxT = (maxTemps[i] as num).toDouble();
        double minT = (minTemps[i] as num).toDouble();

        dailyWeather.add(DailyWeather(
          temp: maxT,
          tempMin: minT,
          tempMax: maxT,
          tempMorning: minT,
          tempDay: maxT,
          tempEvening: (maxT + minT) / 2,
          tempNight: minT,
          weatherCategory: dCond.category,
          condition: dCond.description,
          date: DateTime.parse(dates[i].toString()),
          precipitation:
              '${precips != null && i < precips.length ? precips[i] ?? 0 : 0}%',
          uvi: uvis != null && i < uvis.length ? (uvis[i] as num).toDouble() : 0.0,
          clouds: 0,
          humidity: 0,
        ));
      }
    }
  }

  Future<GeocodeData?> locationToLatLng(String location) async {
    final trimmed = location.trim();
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      try {
        final pincodeUrl =
            'https://aniket-thapa.github.io/india-pincode-api/pincodes/$trimmed.json';
        final res = await http.get(Uri.parse(pincodeUrl));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          Map<String, dynamic>? item;
          if (data is List && data.isNotEmpty) {
            item = data[0] as Map<String, dynamic>;
          } else if (data is Map<String, dynamic>) {
            item = data;
          }
          if (item != null) {
            double? lat = double.tryParse(item['latitude']?.toString() ?? '');
            double? lng = double.tryParse(item['longitude']?.toString() ?? '');
            String name = item['officeName']?.toString() ??
                item['district']?.toString() ??
                item['circleName']?.toString() ??
                trimmed;
            if (lat != null && lng != null) {
              return GeocodeData(name: name, latLng: LatLng(lat, lng));
            }
          }
        }
      } catch (_) {}
    }

    try {
      final geoUrl =
          'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(trimmed)}&count=5&language=en&format=json';
      final res = await http.get(Uri.parse(geoUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['results'] != null && (data['results'] as List).isNotEmpty) {
          final first = data['results'][0];
          String name = first['name']?.toString() ?? trimmed;
          double lat = (first['latitude'] as num).toDouble();
          double lng = (first['longitude'] as num).toDouble();
          return GeocodeData(name: name, latLng: LatLng(lat, lng));
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> searchWeather(String location) async {
    isLoading = true;
    isSearchError = false;
    notifyListeners();

    try {
      GeocodeData? geocodeData = await locationToLatLng(location);
      if (geocodeData != null) {
        await getCurrentWeather(geocodeData.latLng);
        await getDailyWeather(geocodeData.latLng);
        weather.city = geocodeData.name;
      } else {
        isSearchError = true;
      }
    } catch (e) {
      isSearchError = true;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void switchTempUnit() {
    isCelsius = !isCelsius;
    notifyListeners();
  }
}
