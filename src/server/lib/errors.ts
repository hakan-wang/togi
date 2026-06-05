export class AppError extends Error {
  constructor(
    message: string,
    public readonly status = 500
  ) {
    super(message);
  }
}

export const notFound = (resource: string) => new AppError(`${resource} not found`, 404);
export const forbidden = () => new AppError("Forbidden", 403);
export const badRequest = (message: string) => new AppError(message, 400);
