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
            'Location permissions are permanently denied, we cannot request permissions.',
          ),
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
        currentLocation = LatLng(28.6139, 77.2090);
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
    Uri url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&relativehumidity_2m=true&apparent_temperature=true&surface_pressure=true&daily=temperature_2m_max,temperature_2m_min&timezone=auto',
    );
    try {
      final response = await http.get(url);
      final extractedData = json.decode(response.body) as Map<String, dynamic>;
      final currentWeather = extractedData['current_weather'];
      final humidity = extractedData['hourly'] != null
          ? extractedData['hourly']['relativehumidity_2m'][0]
          : 0;
      final apparentTemp = extractedData['hourly'] != null
          ? extractedData['hourly']['apparent_temperature'][0]
          : 0;
      final pressure = extractedData['hourly'] != null
          ? extractedData['hourly']['surface_pressure'][0]
          : 0;
      final dailyMax = extractedData['daily']['temperature_2m_max'][0];
      final dailyMin = extractedData['daily']['temperature_2m_min'][0];

      final wmoCode = currentWeather['weathercode'] as int;
      final conditionMap = mapWmoCode(wmoCode);

      weather = Weather(
        temp: (currentWeather['temperature'] as num).toDouble(),
        tempMax: (dailyMax as num).toDouble(),
        tempMin: (dailyMin as num).toDouble(),
        description: conditionMap.description,
        currently: conditionMap.category,
        wind: (currentWeather['windspeed'] as num).toDouble(),
        cityName: 'Current Location',
      );

      additionalWeatherData = AdditionalWeatherData(
        precipitation: '0',
        humidity: humidity.toString(),
        wind: (currentWeather['windspeed'] as num).toDouble(),
        pressure: pressure.toString(),
      );
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> getDailyWeather(LatLng location) async {
    Uri url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&daily=weathercode,temperature_2m_max,temperature_2m_min&hourly=temperature_2m,weathercode,relativehumidity_2m,windspeed_10m&timezone=auto',
    );
    try {
      final response = await http.get(url);
      final extractedData = json.decode(response.body) as Map<String, dynamic>;
      final dailyData = extractedData['daily'];
      final hourlyData = extractedData['hourly'];

      List<DailyWeather> tempDaily = [];
      List<String> dates = List<String>.from(dailyData['time']);
      List<double> maxTemps =
          List<num>.from(dailyData['temperature_2m_max'])
              .map((e) => e.toDouble())
              .toList();
      List<double> minTemps =
          List<num>.from(dailyData['temperature_2m_min'])
              .map((e) => e.toDouble())
              .toList();
      List<int> codes = List<int>.from(dailyData['weathercode']);

      for (int i = 0; i < dates.length; i++) {
        final cond = mapWmoCode(codes[i]);
        tempDaily.add(
          DailyWeather(
            dailyTemp: maxTemps[i],
            condition: cond.category,
            date: DateTime.parse(dates[i]),
          ),
        );
      }
      dailyWeather = tempDaily;

      List<HourlyWeather> tempHourly = [];
      List<String> hourlyTimes = List<String>.from(hourlyData['time']);
      List<double> hourlyTemps =
          List<num>.from(hourlyData['temperature_2m'])
              .map((e) => e.toDouble())
              .toList();
      List<int> hourlyCodes = List<int>.from(hourlyData['weathercode']);

      for (int i = 0; i < hourlyTimes.length && i < 24; i++) {
        final cond = mapWmoCode(hourlyCodes[i]);
        tempHourly.add(
          HourlyWeather(
            hourlyTemp: hourlyTemps[i],
            condition: cond.category,
            date: DateTime.parse(hourlyTimes[i]),
          ),
        );
      }
      hourlyWeather = tempHourly;
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<void> searchCity(String city) async {
    isSearchError = false;
    isLoading = true;
    notifyListeners();

    try {
      Uri url = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=$city&count=1&language=en&format=json',
      );
      final response = await http.get(url);
      final extractedData = json.decode(response.body) as Map<String, dynamic>;

      if (extractedData['results'] != null &&
          (extractedData['results'] as List).isNotEmpty) {
        final result = extractedData['results'][0];
        final double lat = (result['latitude'] as num).toDouble();
        final double lon = (result['longitude'] as num).toDouble();

        currentLocation = LatLng(lat, lon);
        await getCurrentWeather(currentLocation!);
        await getDailyWeather(currentLocation!);
        weather = Weather(
          temp: weather.temp,
          tempMax: weather.tempMax,
          tempMin: weather.tempMin,
          description: weather.description,
          currently: weather.currently,
          wind: weather.wind,
          cityName: result['name'],
        );
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

  void toggleUnit() {
    isCelsius = !isCelsius;
    notifyListeners();
  }
}
