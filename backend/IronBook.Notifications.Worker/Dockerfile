FROM mcr.microsoft.com/dotnet/runtime:9.0 AS runtime
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY IronBook.sln ./
COPY backend ./backend
RUN dotnet restore IronBook.sln
RUN dotnet publish backend/IronBook.Notifications.Worker/IronBook.Notifications.Worker.csproj -c Release -o /app/publish --no-restore

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "IronBook.Notifications.Worker.dll"]
