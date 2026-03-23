/// Typed exceptions for wandb API errors.
sealed class WandbApiException implements Exception {
  const WandbApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'WandbApiException($statusCode): $message';
}

class AuthenticationException extends WandbApiException {
  const AuthenticationException([String message = 'Invalid API key'])
      : super(message, statusCode: 401);
}

class ForbiddenException extends WandbApiException {
  const ForbiddenException([String message = 'Access denied'])
      : super(message, statusCode: 403);
}

class NotFoundException extends WandbApiException {
  const NotFoundException([String message = 'Resource not found'])
      : super(message, statusCode: 404);
}

class RateLimitException extends WandbApiException {
  const RateLimitException({
    this.retryAfter = const Duration(seconds: 30),
    String message = 'Rate limited',
  }) : super(message, statusCode: 429);

  final Duration retryAfter;
}

class ServerException extends WandbApiException {
  const ServerException([String message = 'Server error'])
      : super(message, statusCode: 500);
}

class NetworkException extends WandbApiException {
  const NetworkException([String message = 'Network unavailable'])
      : super(message);
}

class GraphQLException extends WandbApiException {
  const GraphQLException(this.errors, [String message = 'GraphQL error'])
      : super(message);

  final List<Map<String, dynamic>> errors;

  @override
  String toString() => 'GraphQLException: $errors';
}
