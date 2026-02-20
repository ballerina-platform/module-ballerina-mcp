// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

type WeatherInfo record {|
    string city;
    string country;
    int temperature;
    string condition;
    int humidity;
    int windSpeed;
|};

final map<WeatherInfo> weatherData = {
    "new-york": {
       city: "New York",
       country: "USA",
       temperature: 22,
       condition: "Partly Cloudy",
       humidity: 65,
       windSpeed: 12
    },
    "london": {
       city: "London",
       country: "UK",
       temperature: 18,
       condition: "Rainy",
       humidity: 80,
       windSpeed: 8
    },
    "tokyo": {
       city: "Tokyo",
       country: "Japan",
       temperature: 25,
       condition: "Sunny",
       humidity: 55,
       windSpeed: 6
    },
    "colombo": {
       city: "Colombo",
       country: "Sri Lanka",
       temperature: 30,
       condition: "Tropical",
       humidity: 75,
       windSpeed: 10
    }
};

listener Listener weatherListener = new(3000);

service Service /mcp on weatherListener {

    remote function getWeather(string city) returns CallToolResult {
       if !weatherData.hasKey(city) {
           TextContent textContent = {
              'type: "text",
              text: "Weather not available. Supported: New York, London, Tokyo, Colombo"
            };
            CallToolResult errorResult = {
              content: [textContent],
              isError: true
            };
            return errorResult;
       }

       WeatherInfo? weather = weatherData[city];
       if (weather is ()) {
           TextContent textContent = {
              'type: "text",
              text: "Weather data not found for the specified city."
           };

           CallToolResult errorResult = {
              content: [textContent],
              isError: true
           };
           return errorResult;
       }
       TextContent textContent = {
           'type: "text",
            text: string `Weather in ${weather.city}, ${weather.country} 
                          Temperature: ${weather.temperature}°C 
                          Condition: ${weather.condition} 
                          Humidity: ${weather.humidity}% 
                          Wind Speed: ${weather.windSpeed} kmh`
       };

       CallToolResult result = {
            content: [textContent],
            isError: false
       };
       return result;
    }

    remote function getForecast(string city) returns CallToolResult {

       if !weatherData.hasKey(city) {
           TextContent textContent = {
              'type: "text",
              text: "Forecast not available. Supported: New York, London, Tokyo, Colombo"
           };

           CallToolResult errorResult = {
              content: [textContent],
              isError: true
           };

           return errorResult;
       }

       WeatherInfo? weather = weatherData[city];
       if (weather is ()) {
           TextContent textContent = {
              'type: "text",
              text: "Forecast data not found for the specified city."
           };
       
           CallToolResult errorResult = {
              content: [textContent],
              isError: true
            };
       
            return errorResult;
       }

       TextContent textContent = {
            'type: "text",
            text: string `3-Day Forecast for ${weather.city}, ${weather.country} 
                     Day +1: ${weather.temperature + 1}°C, Sunny 
                     Day +2: ${weather.temperature - 1}°C, Cloudy 
                     Day +3: ${weather.temperature}°C, Rainy`
       };

        CallToolResult result = {
            content: [textContent],
            isError: false
        };

        return result;
    }

    remote function getCityInfo() returns CallToolResult {

       TextContent textContent = {
           'type: "text",
           text: "Supported Cities:\n• New York\n• London\n• Tokyo\n• Colombo"
       };

       CallToolResult result = {
            content: [textContent],
            isError: false
       };

       return result;
    }
}
